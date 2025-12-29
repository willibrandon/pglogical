# pglogical Conflict History Feature

**Target**: pglogical 2.5.0+
**Author**: Brandon
**Status**: Design Proposal

## Overview

Add native conflict history persistence to pglogical. Instead of (or in addition to) logging conflicts via `ereport()`, persist conflict data to a queryable table within the apply worker process.

## Problem Statement

Currently, `pglogical_report_conflict()` logs conflicts via `ereport()` which:
1. Requires parsing log files for conflict analysis
2. Loses data on log rotation
3. Cannot be queried programmatically
4. Cannot trigger alerts or notifications
5. Has no integration with monitoring tools

## Solution

Persist conflicts directly to `pglogical.conflict_history` from within the apply worker, eliminating the need for hooks or external extensions.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    pglogical Apply Worker                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  pglogical_apply_heap.c                                         │
│  ├── handle_insert() ──► conflict detected                     │
│  ├── handle_update() ──► conflict detected                     │
│  └── handle_delete() ──► conflict detected                     │
│           │                                                     │
│           ▼                                                     │
│  try_resolve_conflict()                                         │
│           │                                                     │
│           ▼                                                     │
│  pglogical_report_conflict()  ◄─── ALL DATA AVAILABLE HERE     │
│  ├── [existing] ereport() to server log                        │
│  └── [NEW] pglogical_record_conflict() ──► INSERT to table     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Why This Works

The apply worker already:
- Has a database connection (SPI access)
- Is within a transaction context
- Has all conflict data available in `pglogical_report_conflict()`
- Handles errors gracefully

**No shared memory queue needed.** The apply worker can INSERT directly.

## Implementation

### 1. New GUC Variables

Add to `pglogical.c` in the GUC registration section:

```c
/* Conflict history settings */
bool    pglogical_conflict_history_enabled = false;
bool    pglogical_conflict_history_store_tuples = true;
int     pglogical_conflict_history_max_tuple_size = 1024;
```

```c
DefineCustomBoolVariable("pglogical.conflict_history_enabled",
    "Record conflicts to pglogical.conflict_history table",
    NULL,
    &pglogical_conflict_history_enabled,
    false,  /* default off for backwards compatibility */
    PGC_SIGHUP, 0,
    NULL, NULL, NULL);

DefineCustomBoolVariable("pglogical.conflict_history_store_tuples",
    "Store tuple data in conflict history",
    "When enabled, stores local and remote tuple data as JSONB",
    &pglogical_conflict_history_store_tuples,
    true,
    PGC_SIGHUP, 0,
    NULL, NULL, NULL);

DefineCustomIntVariable("pglogical.conflict_history_max_tuple_size",
    "Maximum bytes per tuple field in conflict history",
    "Tuple data exceeding this size will be truncated",
    &pglogical_conflict_history_max_tuple_size,
    1024, 64, 65536,
    PGC_SIGHUP, 0,
    NULL, NULL, NULL);
```

### 2. Schema Changes

Add to `pglogical--2.4.6--2.5.0.sql` (upgrade script):

```sql
-- Conflict history table
CREATE TABLE pglogical.conflict_history (
    -- Identity
    id                  BIGSERIAL,
    recorded_at         TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    -- Subscription context
    sub_id              OID NOT NULL,
    sub_name            NAME,

    -- Conflict classification
    conflict_type       TEXT NOT NULL CHECK (conflict_type IN (
                            'insert_insert', 'update_update',
                            'update_delete', 'delete_delete')),
    resolution          TEXT NOT NULL CHECK (resolution IN (
                            'apply_remote', 'keep_local', 'skip')),

    -- Affected relation
    schema_name         NAME NOT NULL,
    table_name          NAME NOT NULL,
    index_name          NAME,

    -- Local tuple information (may be NULL for delete conflicts)
    local_tuple         JSONB,
    local_xid           XID,
    local_origin        INTEGER,
    local_commit_ts     TIMESTAMPTZ,

    -- Remote tuple information
    remote_tuple        JSONB,
    remote_origin       INTEGER NOT NULL,
    remote_commit_ts    TIMESTAMPTZ NOT NULL,
    remote_commit_lsn   PG_LSN NOT NULL,

    -- Flags
    has_before_triggers BOOLEAN NOT NULL DEFAULT FALSE,

    PRIMARY KEY (recorded_at, id)
) PARTITION BY RANGE (recorded_at);

-- Create initial partition for current month
DO $$
DECLARE
    start_date DATE := date_trunc('month', CURRENT_DATE);
    end_date DATE := start_date + INTERVAL '1 month';
    partition_name TEXT := 'conflict_history_' || to_char(start_date, 'YYYY_MM');
BEGIN
    EXECUTE format(
        'CREATE TABLE pglogical.%I PARTITION OF pglogical.conflict_history
         FOR VALUES FROM (%L) TO (%L)',
        partition_name, start_date, end_date
    );
END $$;

-- Indexes for common query patterns
CREATE INDEX conflict_history_sub_id_idx
    ON pglogical.conflict_history (sub_id);
CREATE INDEX conflict_history_relation_idx
    ON pglogical.conflict_history (schema_name, table_name);
CREATE INDEX conflict_history_type_idx
    ON pglogical.conflict_history (conflict_type);
CREATE INDEX conflict_history_resolution_idx
    ON pglogical.conflict_history (resolution);

-- Partition management function
CREATE FUNCTION pglogical.conflict_history_ensure_partition(
    target_date DATE DEFAULT CURRENT_DATE
) RETURNS VOID AS $$
DECLARE
    start_date DATE := date_trunc('month', target_date);
    end_date DATE := start_date + INTERVAL '1 month';
    partition_name TEXT := 'conflict_history_' || to_char(start_date, 'YYYY_MM');
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'pglogical' AND c.relname = partition_name
    ) THEN
        EXECUTE format(
            'CREATE TABLE pglogical.%I PARTITION OF pglogical.conflict_history
             FOR VALUES FROM (%L) TO (%L)',
            partition_name, start_date, end_date
        );
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Retention cleanup function
CREATE FUNCTION pglogical.conflict_history_cleanup(
    retention_days INTEGER DEFAULT 30
) RETURNS INTEGER AS $$
DECLARE
    partition_name TEXT;
    dropped_count INTEGER := 0;
BEGIN
    FOR partition_name IN
        SELECT c.relname
        FROM pg_inherits i
        JOIN pg_class c ON c.oid = i.inhrelid
        JOIN pg_class p ON p.oid = i.inhparent
        JOIN pg_namespace n ON n.oid = p.relnamespace
        WHERE n.nspname = 'pglogical'
          AND p.relname = 'conflict_history'
          AND c.relname ~ '^conflict_history_\d{4}_\d{2}$'
          AND to_date(substring(c.relname from 'conflict_history_(\d{4}_\d{2})'), 'YYYY_MM')
              < date_trunc('month', CURRENT_DATE - (retention_days || ' days')::interval)
    LOOP
        EXECUTE format('DROP TABLE pglogical.%I', partition_name);
        dropped_count := dropped_count + 1;
    END LOOP;
    RETURN dropped_count;
END;
$$ LANGUAGE plpgsql;

-- Convenience view: recent conflicts
CREATE VIEW pglogical.recent_conflicts AS
SELECT *
FROM pglogical.conflict_history
WHERE recorded_at > now() - interval '24 hours'
ORDER BY recorded_at DESC;

-- Convenience view: conflict summary by table
CREATE VIEW pglogical.conflict_summary AS
SELECT
    schema_name,
    table_name,
    conflict_type,
    resolution,
    count(*) as conflict_count,
    min(recorded_at) as first_seen,
    max(recorded_at) as last_seen
FROM pglogical.conflict_history
WHERE recorded_at > now() - interval '7 days'
GROUP BY schema_name, table_name, conflict_type, resolution
ORDER BY conflict_count DESC;
```

### 3. C Implementation

#### New file: `pglogical_conflict_history.h`

```c
/*-------------------------------------------------------------------------
 * pglogical_conflict_history.h
 *      Conflict history persistence
 *-------------------------------------------------------------------------
 */
#ifndef PGLOGICAL_CONFLICT_HISTORY_H
#define PGLOGICAL_CONFLICT_HISTORY_H

#include "pglogical_conflict.h"
#include "pglogical_node.h"

extern bool pglogical_conflict_history_enabled;
extern bool pglogical_conflict_history_store_tuples;
extern int  pglogical_conflict_history_max_tuple_size;

extern void pglogical_record_conflict(
    PGLogicalConflictType conflict_type,
    PGLogicalRelation *rel,
    HeapTuple localtuple,
    HeapTuple remotetuple,
    PGLogicalConflictResolution resolution,
    TransactionId local_tuple_xid,
    bool found_local_origin,
    RepOriginId local_tuple_origin,
    TimestampTz local_tuple_commit_ts,
    Oid conflict_idx_oid,
    bool has_before_triggers);

#endif /* PGLOGICAL_CONFLICT_HISTORY_H */
```

#### New file: `pglogical_conflict_history.c`

```c
/*-------------------------------------------------------------------------
 * pglogical_conflict_history.c
 *      Persist conflicts to pglogical.conflict_history table
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/xact.h"
#include "catalog/namespace.h"
#include "executor/spi.h"
#include "replication/origin.h"
#include "utils/builtins.h"
#include "utils/jsonb.h"
#include "utils/lsyscache.h"
#include "utils/rel.h"

#include "pglogical.h"
#include "pglogical_worker.h"
#include "pglogical_conflict_history.h"

/* GUC variables */
bool    pglogical_conflict_history_enabled = false;
bool    pglogical_conflict_history_store_tuples = true;
int     pglogical_conflict_history_max_tuple_size = 1024;

static const char *
conflict_type_to_string(PGLogicalConflictType type)
{
    switch (type)
    {
        case CONFLICT_INSERT_INSERT: return "insert_insert";
        case CONFLICT_UPDATE_UPDATE: return "update_update";
        case CONFLICT_UPDATE_DELETE: return "update_delete";
        case CONFLICT_DELETE_DELETE: return "delete_delete";
    }
    return "unknown";
}

static const char *
resolution_to_string(PGLogicalConflictResolution res)
{
    switch (res)
    {
        case PGLogicalResolution_ApplyRemote: return "apply_remote";
        case PGLogicalResolution_KeepLocal:   return "keep_local";
        case PGLogicalResolution_Skip:        return "skip";
    }
    return "unknown";
}

/*
 * Convert a HeapTuple to JSONB for storage.
 * Truncates values exceeding max_tuple_size.
 */
static Datum
tuple_to_jsonb(TupleDesc tupdesc, HeapTuple tuple, int max_size)
{
    JsonbParseState *state = NULL;
    JsonbValue  jbv;
    int         natt;

    if (tuple == NULL)
        return (Datum) 0;

    pushJsonbValue(&state, WJB_BEGIN_OBJECT, NULL);

    for (natt = 0; natt < tupdesc->natts; natt++)
    {
        Form_pg_attribute attr = TupleDescAttr(tupdesc, natt);
        Datum       val;
        bool        isnull;
        Oid         typoutput;
        bool        typisvarlena;
        char       *outputstr;

        if (attr->attisdropped || attr->attnum < 0)
            continue;

        val = heap_getattr(tuple, natt + 1, tupdesc, &isnull);

        /* Key */
        jbv.type = jbvString;
        jbv.val.string.val = NameStr(attr->attname);
        jbv.val.string.len = strlen(NameStr(attr->attname));
        pushJsonbValue(&state, WJB_KEY, &jbv);

        /* Value */
        if (isnull)
        {
            jbv.type = jbvNull;
            pushJsonbValue(&state, WJB_VALUE, &jbv);
        }
        else
        {
            getTypeOutputInfo(attr->atttypid, &typoutput, &typisvarlena);

            if (typisvarlena && VARATT_IS_EXTERNAL_ONDISK(val))
                outputstr = "(unchanged-toast-datum)";
            else
                outputstr = OidOutputFunctionCall(typoutput, val);

            /* Truncate if too long */
            if (strlen(outputstr) > max_size)
                outputstr[max_size] = '\0';

            jbv.type = jbvString;
            jbv.val.string.val = outputstr;
            jbv.val.string.len = strlen(outputstr);
            pushJsonbValue(&state, WJB_VALUE, &jbv);
        }
    }

    return JsonbPGetDatum(JsonbValueToJsonb(
        pushJsonbValue(&state, WJB_END_OBJECT, NULL)));
}

/*
 * Ensure the conflict_history partition exists for current month.
 */
static void
ensure_partition_exists(void)
{
    int ret;

    ret = SPI_execute(
        "SELECT pglogical.conflict_history_ensure_partition(CURRENT_DATE)",
        false, 0);

    if (ret != SPI_OK_SELECT)
        elog(WARNING, "conflict_history_ensure_partition failed: %d", ret);
}

/*
 * Record a conflict to pglogical.conflict_history.
 * Called from pglogical_report_conflict() when enabled.
 */
void
pglogical_record_conflict(
    PGLogicalConflictType conflict_type,
    PGLogicalRelation *rel,
    HeapTuple localtuple,
    HeapTuple remotetuple,
    PGLogicalConflictResolution resolution,
    TransactionId local_tuple_xid,
    bool found_local_origin,
    RepOriginId local_tuple_origin,
    TimestampTz local_tuple_commit_ts,
    Oid conflict_idx_oid,
    bool has_before_triggers)
{
    TupleDesc   desc;
    Datum       values[16];
    char        nulls[16];
    char        lsn_str[32];
    int         ret;
    Oid         argtypes[16];
    static const char *insert_sql =
        "INSERT INTO pglogical.conflict_history ("
        "  sub_id, sub_name, conflict_type, resolution,"
        "  schema_name, table_name, index_name,"
        "  local_tuple, local_xid, local_origin, local_commit_ts,"
        "  remote_tuple, remote_origin, remote_commit_ts, remote_commit_lsn,"
        "  has_before_triggers"
        ") VALUES ("
        "  $1, $2, $3, $4,"
        "  $5, $6, $7,"
        "  $8, $9, $10, $11,"
        "  $12, $13, $14, $15::pg_lsn,"
        "  $16"
        ")";

    if (!pglogical_conflict_history_enabled)
        return;

    /* We need a subscription context */
    if (MySubscription == NULL)
        return;

    desc = RelationGetDescr(rel->rel);

    /* Connect to SPI if not already connected */
    if (SPI_connect() != SPI_OK_CONNECT)
    {
        elog(WARNING, "pglogical_record_conflict: SPI_connect failed");
        return;
    }

    /* Ensure partition exists (cached, so cheap after first call) */
    ensure_partition_exists();

    memset(nulls, ' ', sizeof(nulls));

    /* $1: sub_id */
    values[0] = ObjectIdGetDatum(MySubscription->id);
    argtypes[0] = OIDOID;

    /* $2: sub_name */
    values[1] = CStringGetDatum(MySubscription->name);
    argtypes[1] = NAMEOID;

    /* $3: conflict_type */
    values[2] = CStringGetTextDatum(conflict_type_to_string(conflict_type));
    argtypes[2] = TEXTOID;

    /* $4: resolution */
    values[3] = CStringGetTextDatum(resolution_to_string(resolution));
    argtypes[3] = TEXTOID;

    /* $5: schema_name */
    values[4] = CStringGetDatum(
        get_namespace_name(RelationGetNamespace(rel->rel)));
    argtypes[4] = NAMEOID;

    /* $6: table_name */
    values[5] = CStringGetDatum(RelationGetRelationName(rel->rel));
    argtypes[5] = NAMEOID;

    /* $7: index_name */
    if (OidIsValid(conflict_idx_oid))
        values[6] = CStringGetDatum(get_rel_name(conflict_idx_oid));
    else
        nulls[6] = 'n';
    argtypes[6] = NAMEOID;

    /* $8: local_tuple */
    if (pglogical_conflict_history_store_tuples && localtuple != NULL)
        values[7] = tuple_to_jsonb(desc, localtuple,
                                   pglogical_conflict_history_max_tuple_size);
    else
        nulls[7] = 'n';
    argtypes[7] = JSONBOID;

    /* $9: local_xid */
    if (TransactionIdIsValid(local_tuple_xid))
        values[8] = TransactionIdGetDatum(local_tuple_xid);
    else
        nulls[8] = 'n';
    argtypes[8] = XIDOID;

    /* $10: local_origin */
    if (found_local_origin)
        values[9] = Int32GetDatum((int32)local_tuple_origin);
    else
        nulls[9] = 'n';
    argtypes[9] = INT4OID;

    /* $11: local_commit_ts */
    if (found_local_origin)
        values[10] = TimestampTzGetDatum(local_tuple_commit_ts);
    else
        nulls[10] = 'n';
    argtypes[10] = TIMESTAMPTZOID;

    /* $12: remote_tuple */
    if (pglogical_conflict_history_store_tuples && remotetuple != NULL)
        values[11] = tuple_to_jsonb(desc, remotetuple,
                                    pglogical_conflict_history_max_tuple_size);
    else
        nulls[11] = 'n';
    argtypes[11] = JSONBOID;

    /* $13: remote_origin */
    values[12] = Int32GetDatum((int32)replorigin_session_origin);
    argtypes[12] = INT4OID;

    /* $14: remote_commit_ts */
    values[13] = TimestampTzGetDatum(replorigin_session_origin_timestamp);
    argtypes[13] = TIMESTAMPTZOID;

    /* $15: remote_commit_lsn */
    snprintf(lsn_str, sizeof(lsn_str), "%X/%X",
             (uint32)(replorigin_session_origin_lsn >> 32),
             (uint32)replorigin_session_origin_lsn);
    values[14] = CStringGetTextDatum(lsn_str);
    argtypes[14] = TEXTOID;

    /* $16: has_before_triggers */
    values[15] = BoolGetDatum(has_before_triggers);
    argtypes[15] = BOOLOID;

    /* Execute the insert */
    ret = SPI_execute_with_args(insert_sql, 16, argtypes, values, nulls,
                                false, 0);

    if (ret != SPI_OK_INSERT)
        elog(WARNING, "conflict_history INSERT failed: %d", ret);

    SPI_finish();
}
```

### 4. Integration with Existing Code

#### Modify `pglogical_conflict.c`

Add to includes:
```c
#include "pglogical_conflict_history.h"
```

Modify `pglogical_report_conflict()` - add before the final `}`:
```c
void
pglogical_report_conflict(...)
{
    /* ... existing ereport() code ... */

    /* Record to conflict_history table if enabled */
    pglogical_record_conflict(
        conflict_type, rel, localtuple, remotetuple,
        resolution, local_tuple_xid, found_local_origin,
        local_tuple_origin, local_tuple_commit_ts,
        conflict_idx_oid, has_before_triggers);
}
```

#### Modify `Makefile`

Add to `OBJS`:
```makefile
OBJS = ... pglogical_conflict_history.o ...
```

### 5. SQL Functions for Monitoring

Add to schema SQL:

```sql
-- Get conflict statistics
CREATE FUNCTION pglogical.conflict_stats(
    OUT total_conflicts BIGINT,
    OUT last_24h BIGINT,
    OUT last_hour BIGINT,
    OUT tables_affected BIGINT
) RETURNS RECORD
LANGUAGE sql STABLE AS $$
    SELECT
        (SELECT count(*) FROM pglogical.conflict_history),
        (SELECT count(*) FROM pglogical.conflict_history
         WHERE recorded_at > now() - interval '24 hours'),
        (SELECT count(*) FROM pglogical.conflict_history
         WHERE recorded_at > now() - interval '1 hour'),
        (SELECT count(DISTINCT (schema_name, table_name))
         FROM pglogical.conflict_history)
$$;

-- Get conflicts for a specific subscription
CREATE FUNCTION pglogical.show_subscription_conflicts(
    subscription_name NAME,
    since TIMESTAMPTZ DEFAULT now() - interval '24 hours',
    max_rows INTEGER DEFAULT 100
) RETURNS SETOF pglogical.conflict_history
LANGUAGE sql STABLE AS $$
    SELECT ch.*
    FROM pglogical.conflict_history ch
    JOIN pglogical.subscription s ON s.sub_id = ch.sub_id
    WHERE s.sub_name = subscription_name
      AND ch.recorded_at > since
    ORDER BY ch.recorded_at DESC
    LIMIT max_rows
$$;
```

## Configuration

### GUC Variables

| Variable | Type | Default | Reload | Description |
|----------|------|---------|--------|-------------|
| `pglogical.conflict_history_enabled` | bool | false | SIGHUP | Enable conflict recording |
| `pglogical.conflict_history_store_tuples` | bool | true | SIGHUP | Store tuple data as JSONB |
| `pglogical.conflict_history_max_tuple_size` | int | 1024 | SIGHUP | Max bytes per tuple field |

### Usage

```sql
-- Enable conflict history
ALTER SYSTEM SET pglogical.conflict_history_enabled = on;
SELECT pg_reload_conf();

-- Query recent conflicts
SELECT * FROM pglogical.recent_conflicts;

-- Get stats
SELECT * FROM pglogical.conflict_stats();

-- Cleanup old data (run periodically)
SELECT pglogical.conflict_history_cleanup(30);  -- Keep 30 days

-- Ensure future partitions exist (run monthly via pg_cron)
SELECT pglogical.conflict_history_ensure_partition(CURRENT_DATE + interval '1 month');
```

## Advantages Over External Extension

1. **No hooks needed** - Direct access in apply worker
2. **No shared memory queue** - Direct INSERT within transaction
3. **Single extension** - No additional installation
4. **Full context available** - Subscription info, relation info, all tuple data
5. **Transactional** - Conflict record commits with the resolution
6. **Simpler architecture** - No background worker coordination

## Backwards Compatibility

- Feature is **disabled by default** (`pglogical.conflict_history_enabled = false`)
- Existing `ereport()` logging continues to work
- No changes to existing behavior unless explicitly enabled
- Upgrade path via standard extension upgrade mechanism

## Testing

Add to `sql/conflict_history.sql`:
```sql
-- Enable conflict history
SET pglogical.conflict_history_enabled = on;

-- Create a conflict scenario
-- (test with bidirectional replication setup)

-- Verify conflict was recorded
SELECT count(*) FROM pglogical.conflict_history;
SELECT * FROM pglogical.recent_conflicts;
SELECT * FROM pglogical.conflict_stats();

-- Test partition management
SELECT pglogical.conflict_history_ensure_partition(CURRENT_DATE + interval '1 month');
SELECT pglogical.conflict_history_cleanup(0);  -- Cleanup all old partitions
```

## Future Enhancements

1. **Alerting triggers** - Allow users to add triggers on conflict_history for notifications
2. **Conflict replay** - Store enough data to manually replay/resolve conflicts
3. **Metrics export** - Prometheus/StatsD integration
4. **Compression** - TOAST compression for large tuple data
5. **Per-subscription configuration** - Enable/disable per subscription

## File Changes Summary

| File | Change |
|------|--------|
| `pglogical.c` | Add GUC definitions |
| `pglogical_conflict.c` | Call `pglogical_record_conflict()` |
| `pglogical_conflict_history.h` | New header file |
| `pglogical_conflict_history.c` | New implementation file |
| `pglogical--2.4.6--2.5.0.sql` | Schema additions |
| `Makefile` | Add new object file |
