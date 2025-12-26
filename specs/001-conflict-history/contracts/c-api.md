# C API Contracts: Conflict History

**Feature**: 001-conflict-history
**Date**: 2025-12-25

This document specifies the C function signatures and behaviors for the conflict history implementation.

## Header: pglogical_conflict_history.h

```c
#ifndef PGLOGICAL_CONFLICT_HISTORY_H
#define PGLOGICAL_CONFLICT_HISTORY_H

#include "pglogical_conflict.h"
#include "pglogical_node.h"

/* GUC variables */
extern bool pglogical_conflict_history_enabled;
extern bool pglogical_conflict_history_store_tuples;
extern int  pglogical_conflict_history_max_tuple_size;

/* Main API */
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

## Function: pglogical_record_conflict

### Signature

```c
void pglogical_record_conflict(
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
```

### Parameters

| Parameter | Type | Nullable | Description |
|-----------|------|----------|-------------|
| `conflict_type` | PGLogicalConflictType | NO | Type of conflict |
| `rel` | PGLogicalRelation* | NO | Relation where conflict occurred |
| `localtuple` | HeapTuple | YES | Existing local tuple (NULL for delete conflicts) |
| `remotetuple` | HeapTuple | YES | Incoming remote tuple (NULL for delete operations) |
| `resolution` | PGLogicalConflictResolution | NO | How conflict was resolved |
| `local_tuple_xid` | TransactionId | - | XID of local tuple (InvalidTransactionId if not available) |
| `found_local_origin` | bool | NO | Whether origin info was found for local tuple |
| `local_tuple_origin` | RepOriginId | - | Origin ID of local tuple (valid only if found_local_origin) |
| `local_tuple_commit_ts` | TimestampTz | - | Commit timestamp of local tuple (valid only if found_local_origin) |
| `conflict_idx_oid` | Oid | - | OID of index where conflict detected (InvalidOid if none) |
| `has_before_triggers` | bool | NO | Whether BEFORE triggers modified remote tuple |

### Behavior

1. **Early exit if disabled**: Returns immediately if `pglogical_conflict_history_enabled` is false
2. **Early exit if no context**: Returns if `MySubscription` is NULL
3. **SPI connection**: Establishes SPI connection
4. **Partition check**: Calls `conflict_history_ensure_partition(CURRENT_DATE)`
5. **Tuple conversion**: Converts tuples to JSONB if `conflict_history_store_tuples` is true
6. **INSERT execution**: Executes parameterized INSERT via SPI
7. **Error handling**: Catches errors via PG_TRY/PG_CATCH, logs WARNING on failure
8. **SPI cleanup**: Finishes SPI connection

### Error Handling

```c
PG_TRY();
{
    /* SPI operations */
}
PG_CATCH();
{
    FlushErrorState();
    elog(WARNING, "conflict_history recording failed, continuing");
}
PG_END_TRY();
```

**Guarantee**: Never aborts the calling transaction.

### Thread Safety

- Not thread-safe (PostgreSQL is single-threaded per backend)
- Uses global `MySubscription` for subscription context
- Uses global `replorigin_session_*` for origin context

### Memory Context

- Runs in MessageContext (same as calling context)
- SPI operations use SPI's memory context
- JSONB conversion allocates in current memory context (freed after SPI_finish)

---

## Internal Function: tuple_to_jsonb

### Signature

```c
static Datum tuple_to_jsonb(
    TupleDesc tupdesc,
    HeapTuple tuple,
    int max_size);
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `tupdesc` | TupleDesc | Tuple descriptor for the relation |
| `tuple` | HeapTuple | Tuple to convert |
| `max_size` | int | Maximum bytes per field value |

### Returns

`Datum` containing JSONB value, or `(Datum) 0` if tuple is NULL.

### Behavior

1. Initializes `JsonbParseState`
2. Iterates through tuple attributes
3. Skips dropped columns and system columns
4. For each attribute:
   - Adds column name as key
   - Adds value (null, string, or "(unchanged-toast-datum)")
   - Truncates values exceeding `max_size`
5. Returns `JsonbPGetDatum(JsonbValueToJsonb(...))`

### Special Cases

| Case | Handling |
|------|----------|
| NULL tuple | Returns `(Datum) 0` |
| NULL field value | Adds `jbvNull` |
| Dropped column | Skips |
| System column (attnum < 0) | Skips |
| External TOAST | Adds `"(unchanged-toast-datum)"` |
| Value > max_size | Truncates at max_size |

---

## Internal Function: ensure_partition_exists

### Signature

```c
static void ensure_partition_exists(void);
```

### Behavior

1. Executes `SELECT pglogical.conflict_history_ensure_partition(CURRENT_DATE)`
2. Logs WARNING if SPI execution fails
3. No-op if partition already exists (idempotent)

### Notes

- Called once per conflict recording
- SQL function handles idempotency
- Partition creation is rare (once per month)

---

## Internal Function: conflict_type_to_string

### Signature

```c
static const char *conflict_type_to_string(PGLogicalConflictType type);
```

### Mapping

| Input | Output |
|-------|--------|
| CONFLICT_INSERT_INSERT | "insert_insert" |
| CONFLICT_UPDATE_UPDATE | "update_update" |
| CONFLICT_UPDATE_DELETE | "update_delete" |
| CONFLICT_DELETE_DELETE | "delete_delete" |
| (other) | "unknown" |

---

## Internal Function: resolution_to_string

### Signature

```c
static const char *resolution_to_string(PGLogicalConflictResolution res);
```

### Mapping

| Input | Output |
|-------|--------|
| PGLogicalResolution_ApplyRemote | "apply_remote" |
| PGLogicalResolution_KeepLocal | "keep_local" |
| PGLogicalResolution_Skip | "skip" |
| (other) | "unknown" |

---

## GUC Registration

Added to `pglogical.c` in `_PG_init()`:

```c
/* pglogical.conflict_history_enabled */
DefineCustomBoolVariable(
    "pglogical.conflict_history_enabled",
    "Record conflicts to pglogical.conflict_history table",
    NULL,
    &pglogical_conflict_history_enabled,
    false,                    /* default: off */
    PGC_SIGHUP,              /* reloadable */
    0,
    NULL, NULL, NULL);

/* pglogical.conflict_history_store_tuples */
DefineCustomBoolVariable(
    "pglogical.conflict_history_store_tuples",
    "Store tuple data in conflict history",
    "When enabled, stores local and remote tuple data as JSONB",
    &pglogical_conflict_history_store_tuples,
    true,                    /* default: on */
    PGC_SIGHUP,
    0,
    NULL, NULL, NULL);

/* pglogical.conflict_history_max_tuple_size */
DefineCustomIntVariable(
    "pglogical.conflict_history_max_tuple_size",
    "Maximum bytes per tuple field in conflict history",
    "Tuple data exceeding this size will be truncated",
    &pglogical_conflict_history_max_tuple_size,
    1024,                    /* default */
    64,                      /* min */
    65536,                   /* max */
    PGC_SIGHUP,
    0,
    NULL, NULL, NULL);
```

---

## Integration Point

### Modification to pglogical_conflict.c

```c
#include "pglogical_conflict_history.h"

void
pglogical_report_conflict(
    PGLogicalConflictType conflict_type,
    PGLogicalRelation *rel,
    HeapTuple localtuple,
    PGLogicalTupleData *oldkey,
    HeapTuple remotetuple,
    HeapTuple applytuple,
    PGLogicalConflictResolution resolution,
    TransactionId local_tuple_xid,
    bool found_local_origin,
    RepOriginId local_tuple_origin,
    TimestampTz local_tuple_commit_ts,
    Oid conflict_idx_oid,
    bool has_before_triggers)
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

---

## Dependencies

### Includes Required

```c
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
```

### Global Variables Used

| Variable | Header | Purpose |
|----------|--------|---------|
| `MySubscription` | pglogical_worker.h | Current subscription context |
| `replorigin_session_origin` | replication/origin.h | Remote origin ID |
| `replorigin_session_origin_timestamp` | replication/origin.h | Remote commit timestamp |
| `replorigin_session_origin_lsn` | replication/origin.h | Remote commit LSN |

---

## Makefile Addition

```makefile
OBJS = \
    pglogical.o \
    pglogical_apply.o \
    pglogical_apply_heap.o \
    pglogical_apply_spi.o \
    pglogical_conflict.o \
    pglogical_conflict_history.o \     # NEW
    ... (rest of objects)
```
