# Feature: Improved Lag Tracking

## Overview

This feature adds improved replication lag tracking to pglogical with a new `pglogical.lag_tracker` view that provides accurate, subscriber-side lag measurement. Unlike provider-side estimation, this approach calculates lag at the target node where transactions are applied, providing more accurate real-time metrics.

## Current State

pglogical currently has:
- `pglogical_wait_slot_confirm_lsn()` - Wait for slot confirmed_flush to pass a position
- Basic slot-based monitoring via PostgreSQL's `pg_replication_slots`
- No dedicated lag tracking infrastructure
- No subscriber-side progress tracking

What's missing:
- Shared memory infrastructure for tracking apply progress
- Per-subscription lag metrics (bytes and time)
- Subscriber-side progress view
- Real-time lag calculation based on commit timestamps

## Design

### Key Metrics

| Metric | Description |
|--------|-------------|
| `commit_timestamp` | Commit time of the last transaction received from the provider |
| `commit_lsn` | LSN of the last commit applied from the provider |
| `remote_insert_lsn` | WAL insert position on the provider when the commit was sent |
| `replication_lag_bytes` | Difference between remote_insert_lsn and commit_lsn |
| `replication_lag` | Time delay between provider commit and subscriber apply |

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Provider Node                                    │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐             │
│  │   WAL       │───▶│  Output     │───▶│  Streaming  │             │
│  │   Writer    │    │  Plugin     │    │  Connection │             │
│  └─────────────┘    └─────────────┘    └──────┬──────┘             │
│                                               │                      │
│  Sends: commit_lsn, commit_time, remote_insert_lsn                  │
└───────────────────────────────────────────────┼─────────────────────┘
                                                │
                                                ▼
┌───────────────────────────────────────────────┼─────────────────────┐
│                     Subscriber Node           │                      │
│                                               ▼                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    Apply Worker                              │   │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐      │   │
│  │  │   Receive   │───▶│   Apply     │───▶│   Update    │      │   │
│  │  │   Message   │    │   Changes   │    │   Progress  │      │   │
│  │  └─────────────┘    └─────────────┘    └──────┬──────┘      │   │
│  └───────────────────────────────────────────────┼──────────────┘   │
│                                                  │                   │
│                                                  ▼                   │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              Shared Memory (PGLogicalApplyProgress)          │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ node_id | remote_node_id | commit_ts | commit_lsn | ... │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  └───────────────────────────────────────────────┬──────────────┘   │
│                                                  │                   │
│                                                  ▼                   │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │           pglogical.lag_tracker View                         │   │
│  │  origin_name | receiver_name | commit_lsn | lag_bytes | lag  │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### Lag Calculation

**Time-based lag:**
```
replication_lag = last_updated_ts - remote_commit_ts
```
Where:
- `remote_commit_ts` = Timestamp when transaction committed on provider
- `last_updated_ts` = Timestamp when transaction was applied on subscriber

**Byte-based lag:**
```
replication_lag_bytes = pg_wal_lsn_diff(remote_insert_lsn, commit_lsn)
```
Where:
- `remote_insert_lsn` = Provider's WAL insert position at commit time
- `commit_lsn` = LSN of the commit that was just applied

## Implementation

### File Structure

```
pglogical/
├── pglogical_lag_tracker.c   # New file - Lag tracking logic
├── pglogical_lag_tracker.h   # New file - Header
├── pglogical_apply.c         # Modified - Update progress on commit
├── pglogical_worker.c        # Modified - Shared memory setup
├── pglogical.c               # Modified - Shared memory hooks
└── sql/pglogical--X.Y.Z.sql  # Modified - Add views
```

### Header File: pglogical_lag_tracker.h

```c
/*-------------------------------------------------------------------------
 *
 * pglogical_lag_tracker.h
 *      pglogical replication lag tracking
 *
 * Copyright (c) 2015-2025, PostgreSQL Global Development Group
 *
 *-------------------------------------------------------------------------
 */
#ifndef PGLOGICAL_LAG_TRACKER_H
#define PGLOGICAL_LAG_TRACKER_H

#include "postgres.h"
#include "datatype/timestamp.h"
#include "storage/lwlock.h"
#include "utils/hsearch.h"

/*
 * Key for identifying a subscription's progress entry.
 */
typedef struct PGLogicalProgressKey
{
    Oid     dbid;           /* Database OID */
    Oid     node_id;        /* Local (subscriber) node ID */
    Oid     remote_node_id; /* Remote (provider) node ID */
} PGLogicalProgressKey;

/*
 * PGLogicalApplyProgress
 *
 * Tracks the progress of applying remote transactions for lag calculation.
 *
 * remote_commit_ts - Timestamp when the transaction committed on the provider.
 * remote_commit_lsn - LSN of the COMMIT record on the provider.
 * remote_insert_lsn - Provider's WAL insert position when commit was sent.
 *                     Used to calculate byte lag.
 * received_lsn - Most advanced LSN received by the apply worker.
 * last_updated_ts - Timestamp when this progress entry was last updated.
 *                   Used with remote_commit_ts to calculate time lag.
 */
typedef struct PGLogicalApplyProgress
{
    PGLogicalProgressKey key;           /* Hash key */
    TimestampTz remote_commit_ts;       /* Provider commit timestamp */
    TimestampTz prev_remote_ts;         /* Previous remote timestamp */
    XLogRecPtr  remote_commit_lsn;      /* Provider commit LSN */
    XLogRecPtr  remote_insert_lsn;      /* Provider insert LSN at commit */
    XLogRecPtr  received_lsn;           /* Latest received LSN */
    TimestampTz last_updated_ts;        /* When we applied the commit */
} PGLogicalApplyProgress;

/*
 * Hash table entry for progress tracking.
 */
typedef struct PGLogicalProgressEntry
{
    PGLogicalProgressKey key;           /* Hash key */
    PGLogicalApplyProgress progress;    /* Progress data */
    pg_atomic_uint32 nattached;         /* Number of attached workers */
} PGLogicalProgressEntry;

/* Shared memory setup */
extern void pglogical_lag_tracker_shmem_request(void);
extern void pglogical_lag_tracker_shmem_startup(void);

/* Progress tracking functions */
extern PGLogicalProgressEntry *pglogical_progress_attach(Oid dbid, Oid node_id,
                                                          Oid remote_node_id);
extern void pglogical_progress_detach(void);
extern void pglogical_progress_update(const PGLogicalApplyProgress *progress);
extern PGLogicalApplyProgress *pglogical_progress_get(void);

/* SQL-callable function */
extern Datum pglogical_apply_progress(PG_FUNCTION_ARGS);

/* Global hash table */
extern HTAB *PGLogicalProgressHash;

#endif /* PGLOGICAL_LAG_TRACKER_H */
```

### Source File: pglogical_lag_tracker.c

```c
/*-------------------------------------------------------------------------
 *
 * pglogical_lag_tracker.c
 *      pglogical replication lag tracking
 *
 * This module manages shared memory tracking of apply progress for
 * calculating replication lag on the subscriber side.
 *
 * Copyright (c) 2015-2025, PostgreSQL Global Development Group
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "funcapi.h"
#include "miscadmin.h"

#include "access/htup_details.h"
#include "catalog/pg_type.h"
#include "common/hashfn.h"
#include "datatype/timestamp.h"
#include "storage/ipc.h"
#include "storage/lwlock.h"
#include "storage/shmem.h"
#include "utils/builtins.h"
#include "utils/hsearch.h"
#include "utils/timestamp.h"

#include "pglogical_lag_tracker.h"
#include "pglogical_worker.h"
#include "pglogical.h"

/* Shared memory hash table for progress tracking */
HTAB *PGLogicalProgressHash = NULL;

/* LWLock for protecting the hash table */
static LWLockId ProgressHashLock = NULL;

/* Current worker's progress entry */
static PGLogicalProgressEntry *MyProgressEntry = NULL;

/* Previous shmem hooks */
#if PG_VERSION_NUM >= 150000
static shmem_request_hook_type prev_shmem_request_hook = NULL;
#endif
static shmem_startup_hook_type prev_shmem_startup_hook = NULL;

PG_FUNCTION_INFO_V1(pglogical_apply_progress);

/*
 * pglogical_lag_tracker_shmem_request
 *
 * Request shared memory for the progress hash table.
 */
void
pglogical_lag_tracker_shmem_request(void)
{
    Size size;
    int  max_entries;

#if PG_VERSION_NUM >= 150000
    if (prev_shmem_request_hook)
        prev_shmem_request_hook();
#endif

    /* Use max_worker_processes as upper bound */
    max_entries = atoi(GetConfigOptionByName("max_worker_processes", NULL, false));
    if (max_entries <= 0)
        max_entries = 8;

    /* Request shared memory */
    size = hash_estimate_size(max_entries, sizeof(PGLogicalProgressEntry));
    RequestAddinShmemSpace(size);

    /* Request LWLock */
    RequestNamedLWLockTranche("pglogical_progress", 1);
}

/*
 * pglogical_lag_tracker_shmem_startup
 *
 * Initialize the shared memory hash table.
 */
void
pglogical_lag_tracker_shmem_startup(void)
{
    HASHCTL     hctl;
    bool        found;
    int         max_entries;

    if (prev_shmem_startup_hook)
        prev_shmem_startup_hook();

    /* Already initialized? */
    if (PGLogicalProgressHash != NULL)
        return;

    max_entries = atoi(GetConfigOptionByName("max_worker_processes", NULL, false));
    if (max_entries <= 0)
        max_entries = 8;

    /* Get our LWLock */
    ProgressHashLock = &(GetNamedLWLockTranche("pglogical_progress"))->lock;

    /* Initialize hash table */
    memset(&hctl, 0, sizeof(hctl));
    hctl.keysize = sizeof(PGLogicalProgressKey);
    hctl.entrysize = sizeof(PGLogicalProgressEntry);
    hctl.hash = tag_hash;

    PGLogicalProgressHash = ShmemInitHash("pglogical progress hash",
                                           max_entries,
                                           max_entries,
                                           &hctl,
                                           HASH_ELEM | HASH_BLOBS |
                                           HASH_SHARED_MEM | HASH_FIXED_SIZE);

    if (!PGLogicalProgressHash)
        elog(ERROR, "could not initialize pglogical progress hash");
}

/*
 * pglogical_progress_attach
 *
 * Attach to a progress entry for the given subscription.
 * Creates entry if it doesn't exist.
 */
PGLogicalProgressEntry *
pglogical_progress_attach(Oid dbid, Oid node_id, Oid remote_node_id)
{
    PGLogicalProgressKey key;
    PGLogicalProgressEntry *entry;
    bool found;

    memset(&key, 0, sizeof(key));
    key.dbid = dbid;
    key.node_id = node_id;
    key.remote_node_id = remote_node_id;

    LWLockAcquire(ProgressHashLock, LW_EXCLUSIVE);

    entry = (PGLogicalProgressEntry *)
        hash_search(PGLogicalProgressHash, &key, HASH_ENTER, &found);

    if (!found)
    {
        /* Initialize new entry */
        memset(&entry->progress, 0, sizeof(PGLogicalApplyProgress));
        entry->progress.key = key;
        entry->progress.remote_commit_lsn = InvalidXLogRecPtr;
        entry->progress.remote_insert_lsn = InvalidXLogRecPtr;
        entry->progress.received_lsn = InvalidXLogRecPtr;
        pg_atomic_init_u32(&entry->nattached, 0);
    }

    pg_atomic_fetch_add_u32(&entry->nattached, 1);

    LWLockRelease(ProgressHashLock);

    MyProgressEntry = entry;
    return entry;
}

/*
 * pglogical_progress_detach
 *
 * Detach from current progress entry.
 */
void
pglogical_progress_detach(void)
{
    if (MyProgressEntry == NULL)
        return;

    pg_atomic_fetch_sub_u32(&MyProgressEntry->nattached, 1);
    MyProgressEntry = NULL;
}

/*
 * pglogical_progress_update
 *
 * Update the progress entry with new values.
 * Only updates fields that have advanced.
 */
void
pglogical_progress_update(const PGLogicalApplyProgress *progress)
{
    PGLogicalProgressEntry *entry = MyProgressEntry;

    if (entry == NULL)
        return;

    LWLockAcquire(ProgressHashLock, LW_EXCLUSIVE);

    /* Update commit info if LSN has advanced */
    if (progress->remote_commit_lsn > entry->progress.remote_commit_lsn)
    {
        entry->progress.prev_remote_ts = entry->progress.remote_commit_ts;
        entry->progress.remote_commit_ts = progress->remote_commit_ts;
        entry->progress.remote_commit_lsn = progress->remote_commit_lsn;
        entry->progress.last_updated_ts = progress->last_updated_ts;
    }

    /* Update insert LSN if advanced */
    if (progress->remote_insert_lsn > entry->progress.remote_insert_lsn)
        entry->progress.remote_insert_lsn = progress->remote_insert_lsn;

    /* Update received LSN if advanced */
    if (progress->received_lsn > entry->progress.received_lsn)
        entry->progress.received_lsn = progress->received_lsn;

    LWLockRelease(ProgressHashLock);
}

/*
 * pglogical_progress_get
 *
 * Get current progress for this worker.
 */
PGLogicalApplyProgress *
pglogical_progress_get(void)
{
    if (MyProgressEntry == NULL)
        return NULL;
    return &MyProgressEntry->progress;
}

/*
 * pglogical_apply_progress
 *
 * SQL function returning all progress entries for the current database.
 */
Datum
pglogical_apply_progress(PG_FUNCTION_ARGS)
{
    ReturnSetInfo *rsinfo = (ReturnSetInfo *) fcinfo->resultinfo;
    TupleDesc       tupdesc;
    Tuplestorestate *tupstore;
    MemoryContext   per_query_ctx;
    MemoryContext   oldcontext;
    HASH_SEQ_STATUS hash_seq;
    PGLogicalProgressEntry *entry;
    Oid             current_dbid = MyDatabaseId;

    /* Check result set mode */
    if (rsinfo == NULL || !IsA(rsinfo, ReturnSetInfo))
        ereport(ERROR,
                (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                 errmsg("set-valued function called in context that cannot accept a set")));
    if (!(rsinfo->allowedModes & SFRM_Materialize))
        ereport(ERROR,
                (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                 errmsg("materialize mode required, but it is not allowed in this context")));

    /* Build tuple descriptor */
    if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
        elog(ERROR, "return type must be a row type");

    per_query_ctx = rsinfo->econtext->ecxt_per_query_memory;
    oldcontext = MemoryContextSwitchTo(per_query_ctx);

    tupstore = tuplestore_begin_heap(true, false, work_mem);
    rsinfo->returnMode = SFRM_Materialize;
    rsinfo->setResult = tupstore;
    rsinfo->setDesc = tupdesc;

    MemoryContextSwitchTo(oldcontext);

    /* Return empty if hash not initialized */
    if (PGLogicalProgressHash == NULL)
        return (Datum) 0;

    /* Scan the hash table */
    LWLockAcquire(ProgressHashLock, LW_SHARED);
    hash_seq_init(&hash_seq, PGLogicalProgressHash);

    while ((entry = hash_seq_search(&hash_seq)) != NULL)
    {
        Datum       values[9];
        bool        nulls[9] = {false};

        /* Filter by current database */
        if (entry->key.dbid != current_dbid)
            continue;

        /* dbid */
        values[0] = ObjectIdGetDatum(entry->key.dbid);

        /* node_id */
        values[1] = ObjectIdGetDatum(entry->key.node_id);

        /* remote_node_id */
        values[2] = ObjectIdGetDatum(entry->key.remote_node_id);

        /* remote_commit_ts */
        if (entry->progress.remote_commit_ts != 0)
            values[3] = TimestampTzGetDatum(entry->progress.remote_commit_ts);
        else
            nulls[3] = true;

        /* prev_remote_ts */
        if (entry->progress.prev_remote_ts != 0)
            values[4] = TimestampTzGetDatum(entry->progress.prev_remote_ts);
        else
            nulls[4] = true;

        /* remote_commit_lsn */
        values[5] = LSNGetDatum(entry->progress.remote_commit_lsn);

        /* remote_insert_lsn */
        values[6] = LSNGetDatum(entry->progress.remote_insert_lsn);

        /* received_lsn */
        values[7] = LSNGetDatum(entry->progress.received_lsn);

        /* last_updated_ts */
        if (entry->progress.last_updated_ts != 0)
            values[8] = TimestampTzGetDatum(entry->progress.last_updated_ts);
        else
            nulls[8] = true;

        tuplestore_putvalues(tupstore, tupdesc, values, nulls);
    }

    LWLockRelease(ProgressHashLock);

    return (Datum) 0;
}
```

### Modifications to pglogical_apply.c

Add progress update at commit time:

```c
#include "pglogical_lag_tracker.h"

/* Static progress tracking variable */
static PGLogicalApplyProgress apply_progress = {
    .remote_commit_ts = 0,
    .prev_remote_ts = 0,
    .remote_commit_lsn = InvalidXLogRecPtr,
    .remote_insert_lsn = InvalidXLogRecPtr,
    .received_lsn = InvalidXLogRecPtr,
    .last_updated_ts = 0
};

/*
 * Update progress on receiving WAL records
 */
static void
update_worker_progress(XLogRecPtr received_lsn, XLogRecPtr insert_lsn)
{
    apply_progress.received_lsn = received_lsn;
    apply_progress.remote_insert_lsn = insert_lsn;
    pglogical_progress_update(&apply_progress);
}

/*
 * In handle_commit(), after successful commit:
 */
static void
handle_commit(StringInfo s)
{
    XLogRecPtr  commit_lsn;
    XLogRecPtr  end_lsn;
    TimestampTz commit_time;
    XLogRecPtr  remote_insert_lsn;

    /* Read commit message */
    pglogical_read_commit(s, &commit_lsn, &end_lsn, &commit_time,
                          &remote_insert_lsn);

    /* ... existing commit handling ... */

    /* Update progress after successful commit */
    {
        PGLogicalApplyProgress progress = {
            .key.dbid = MyDatabaseId,
            .key.node_id = MySubscription->target->id,
            .key.remote_node_id = MySubscription->origin->id,
            .remote_commit_ts = commit_time,
            .prev_remote_ts = apply_progress.remote_commit_ts,
            .remote_commit_lsn = commit_lsn,
            .remote_insert_lsn = remote_insert_lsn,
            .received_lsn = end_lsn,
            .last_updated_ts = GetCurrentTimestamp()
        };

        pglogical_progress_update(&progress);
    }

    /* ... rest of commit handling ... */
}
```

### Modifications to pglogical_worker.c

Attach to progress tracking in apply worker startup:

```c
#include "pglogical_lag_tracker.h"

void
pglogical_apply_main(Datum main_arg)
{
    /* ... existing initialization ... */

    /* Attach to progress tracking */
    pglogical_progress_attach(MyDatabaseId,
                              MySubscription->target->id,
                              MySubscription->origin->id);

    /* ... rest of main loop ... */

    /* Cleanup: detach from progress tracking */
    pglogical_progress_detach();
}
```

### Modifications to pglogical.c

Add shared memory hooks:

```c
#include "pglogical_lag_tracker.h"

void
_PG_init(void)
{
    /* ... existing init ... */

    /* Request lag tracker shared memory */
    pglogical_lag_tracker_shmem_request();

    /* ... rest of init ... */
}

/* In shmem startup hook */
static void
pglogical_shmem_startup(void)
{
    /* ... existing startup ... */

    /* Initialize lag tracker */
    pglogical_lag_tracker_shmem_startup();
}
```

### Protocol Extension

Modify `pglogical_proto_native.c` to include remote_insert_lsn in COMMIT messages:

```c
/*
 * Write COMMIT message - include remote insert LSN for lag calculation
 */
void
pglogical_write_commit(StringInfo out, XLogRecPtr commit_lsn,
                       XLogRecPtr end_lsn, TimestampTz commit_time)
{
    uint8   flags = 0;

    pq_sendbyte(out, 'C');      /* COMMIT */
    pq_sendbyte(out, flags);
    pq_sendint64(out, commit_lsn);
    pq_sendint64(out, end_lsn);
    pq_sendint64(out, commit_time);

    /* Protocol version 2+: include remote insert LSN */
    pq_sendint64(out, GetXLogInsertRecPtr());
}

/*
 * Read COMMIT message
 */
void
pglogical_read_commit(StringInfo in, XLogRecPtr *commit_lsn,
                      XLogRecPtr *end_lsn, TimestampTz *commit_time,
                      XLogRecPtr *remote_insert_lsn)
{
    /* ... read existing fields ... */

    /* Read remote insert LSN if available (protocol v2+) */
    if (in->cursor < in->len)
        *remote_insert_lsn = pq_getmsgint64(in);
    else
        *remote_insert_lsn = InvalidXLogRecPtr;
}
```

### SQL Schema

Add to `pglogical--X.Y.Z.sql`:

```sql
-- Progress tracking function (reads shared memory)
CREATE FUNCTION pglogical.apply_progress(
    OUT dbid              oid,
    OUT node_id           oid,
    OUT remote_node_id    oid,
    OUT remote_commit_ts  timestamptz,
    OUT prev_remote_ts    timestamptz,
    OUT remote_commit_lsn pg_lsn,
    OUT remote_insert_lsn pg_lsn,
    OUT received_lsn      pg_lsn,
    OUT last_updated_ts   timestamptz
) RETURNS SETOF record
LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_apply_progress';

-- Progress view filtered to current database
CREATE VIEW pglogical.progress AS
    SELECT * FROM pglogical.apply_progress()
    WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database());

-- Lag tracker view with calculated lag metrics
CREATE VIEW pglogical.lag_tracker AS
    SELECT
        origin.node_name AS origin_name,
        n.node_name AS receiver_name,
        MAX(p.remote_commit_ts) AS commit_timestamp,
        MAX(p.remote_commit_lsn) AS commit_lsn,
        MAX(p.remote_insert_lsn) AS remote_insert_lsn,
        CASE
            WHEN MAX(p.remote_insert_lsn) IS NOT NULL
                 AND MAX(p.remote_commit_lsn) IS NOT NULL
            THEN MAX(pg_wal_lsn_diff(p.remote_insert_lsn, p.remote_commit_lsn))
            ELSE NULL
        END AS replication_lag_bytes,
        CASE
            WHEN MAX(p.remote_commit_ts) IS NOT NULL
                 AND MAX(p.last_updated_ts) IS NOT NULL
            THEN MAX(p.last_updated_ts - p.remote_commit_ts)
            ELSE NULL
        END AS replication_lag
    FROM pglogical.progress p
    LEFT JOIN pglogical.subscription sub
        ON (p.node_id = sub.sub_target AND p.remote_node_id = sub.sub_origin)
    LEFT JOIN pglogical.node origin
        ON sub.sub_origin = origin.node_id
    LEFT JOIN pglogical.node n
        ON n.node_id = p.node_id
    GROUP BY origin.node_name, n.node_name;

COMMENT ON VIEW pglogical.lag_tracker IS
'Shows replication lag metrics for each subscription.

Columns:
  origin_name           - Name of the provider node
  receiver_name         - Name of the subscriber node
  commit_timestamp      - Timestamp of last applied commit from provider
  commit_lsn            - LSN of last applied commit
  remote_insert_lsn     - Provider WAL insert position at commit time
  replication_lag_bytes - Bytes behind provider (insert_lsn - commit_lsn)
  replication_lag       - Time delay (apply_time - commit_time)
';
```

### Modifications to Makefile

Add the new object file:

```makefile
OBJS = pglogical_apply.o pglogical_conflict.o pglogical_manager.o \
       pglogical_node.o pglogical_relcache.o pglogical_repset.o \
       pglogical_rpc.o pglogical_functions.o pglogical_queue.o \
       pglogical_fe.o pglogical.o pglogical_sync.o pglogical_worker.o \
       pglogical_output.o pglogical_executor.o pglogical_dependency.o \
       pglogical_apply_heap.o pglogical_apply_spi.o pglogical_output_config.o \
       pglogical_output_plugin.o pglogical_output_proto.o \
       pglogical_proto_json.o pglogical_proto_native.o \
       pglogical_monitoring.o pglogical_sequences.o \
       pglogical_conflict_history.o pglogical_autoddl.o \
       pglogical_lag_tracker.o
```

## Usage

### Query Replication Lag

```sql
-- View lag for all subscriptions
SELECT * FROM pglogical.lag_tracker;

-- Example output:
--  origin_name | receiver_name | commit_timestamp          | commit_lsn | remote_insert_lsn | replication_lag_bytes | replication_lag
-- -------------+---------------+---------------------------+------------+-------------------+-----------------------+------------------
--  provider1   | subscriber1   | 2025-01-05 10:30:45+00    | 0/15A2780  | 0/15A2780        | 0                     | 00:00:00.012345
--  provider2   | subscriber1   | 2025-01-05 10:30:44+00    | 0/12B3000  | 0/12B4500        | 5376                  | 00:00:01.234567
```

### Monitor Lag in Real-Time

```sql
-- Check lag every second
\watch 1
SELECT
    origin_name,
    receiver_name,
    commit_lsn,
    pg_size_pretty(replication_lag_bytes) AS lag_bytes,
    replication_lag
FROM pglogical.lag_tracker;
```

### Alert on High Lag

```sql
-- Check if any subscription is more than 1 minute behind
SELECT origin_name, receiver_name, replication_lag
FROM pglogical.lag_tracker
WHERE replication_lag > interval '1 minute';
```

### Raw Progress Data

```sql
-- View raw progress data for debugging
SELECT
    node_id,
    remote_node_id,
    remote_commit_ts,
    remote_commit_lsn,
    remote_insert_lsn,
    last_updated_ts,
    last_updated_ts - remote_commit_ts AS calculated_lag
FROM pglogical.progress;
```

## Testing

### Regression Test: sql/lag_tracker.sql

```sql
-- Test lag tracker functionality
\set VERBOSITY terse

-- Setup: create provider and subscriber nodes
SELECT pglogical.create_node('provider_node', 'dbname=' || current_database());
SELECT pglogical.create_node('subscriber_node', 'dbname=' || current_database());

-- Verify progress view exists and returns correct columns
SELECT
    count(*) = 0 AS no_progress_initially
FROM pglogical.progress;

-- Verify lag_tracker view exists
SELECT
    attname
FROM pg_attribute
WHERE attrelid = 'pglogical.lag_tracker'::regclass
  AND attnum > 0
ORDER BY attnum;

-- Expected columns:
-- origin_name
-- receiver_name
-- commit_timestamp
-- commit_lsn
-- remote_insert_lsn
-- replication_lag_bytes
-- replication_lag

-- Verify apply_progress function returns correct types
SELECT
    proname,
    pg_get_function_result(oid)
FROM pg_proc
WHERE proname = 'apply_progress'
  AND pronamespace = 'pglogical'::regnamespace;

-- Cleanup
SELECT pglogical.drop_node('subscriber_node');
SELECT pglogical.drop_node('provider_node');
```

### Integration Test

```bash
#!/bin/bash
# Test lag tracking with actual replication

# Setup two-node replication
# ... setup code ...

# Insert data on provider
psql -h provider -c "INSERT INTO test_table SELECT generate_series(1, 10000);"

# Check lag on subscriber
psql -h subscriber -c "SELECT * FROM pglogical.lag_tracker;"

# Verify lag decreases as subscriber catches up
for i in {1..10}; do
    psql -h subscriber -c "
        SELECT
            replication_lag_bytes,
            replication_lag
        FROM pglogical.lag_tracker;
    "
    sleep 1
done
```

## Configuration

No new GUC settings are required. The feature uses existing shared memory allocation based on `max_worker_processes`.

## Limitations

1. **Shared memory persistence** - Progress data is lost on server restart. The view will show empty until apply workers reconnect and start processing.

2. **Protocol version** - Full lag calculation requires protocol version 2+ for the `remote_insert_lsn` field. Older providers will only provide time-based lag.

3. **Clock synchronization** - Time-based lag (`replication_lag`) accuracy depends on synchronized clocks between provider and subscriber. Consider using NTP.

4. **Sampling rate** - Progress is updated on each commit. High-frequency small transactions will show accurate lag; large batch transactions may show stale lag until commit.

## Migration Notes

### Upgrading

The `pglogical.lag_tracker` view and `pglogical.progress` view are automatically created during extension upgrade. No manual migration is required.

### Backward Compatibility

- Older subscribers connecting to newer providers will work but won't receive `remote_insert_lsn`
- `replication_lag_bytes` will be NULL in this case
- Time-based `replication_lag` will still work

## References

- PostgreSQL logical replication documentation
- PostgreSQL shared memory and LWLock documentation
- pglogical existing monitoring infrastructure
