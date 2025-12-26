# Data Model: Conflict History Persistence

**Feature**: 001-conflict-history
**Date**: 2025-12-25

## Entity Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        pglogical.conflict_history                       │
│                    (Partitioned Table - Monthly by recorded_at)         │
├─────────────────────────────────────────────────────────────────────────┤
│  IDENTITY                                                               │
│  ├── id: BIGSERIAL                                                      │
│  └── recorded_at: TIMESTAMPTZ (partition key)                           │
│                                                                         │
│  SUBSCRIPTION CONTEXT                                                   │
│  ├── sub_id: OID                                                        │
│  └── sub_name: NAME                                                     │
│                                                                         │
│  CONFLICT CLASSIFICATION                                                │
│  ├── conflict_type: TEXT (insert_insert|update_update|...)             │
│  └── resolution: TEXT (apply_remote|keep_local|skip)                   │
│                                                                         │
│  RELATION CONTEXT                                                       │
│  ├── schema_name: NAME                                                  │
│  ├── table_name: NAME                                                   │
│  └── index_name: NAME (nullable)                                        │
│                                                                         │
│  LOCAL TUPLE STATE                                                      │
│  ├── local_tuple: JSONB (nullable)                                      │
│  ├── local_xid: XID (nullable)                                          │
│  ├── local_origin: INTEGER (nullable)                                   │
│  └── local_commit_ts: TIMESTAMPTZ (nullable)                            │
│                                                                         │
│  REMOTE TUPLE STATE                                                     │
│  ├── remote_tuple: JSONB (nullable)                                     │
│  ├── remote_origin: INTEGER                                             │
│  ├── remote_commit_ts: TIMESTAMPTZ                                      │
│  └── remote_commit_lsn: PG_LSN                                          │
│                                                                         │
│  FLAGS                                                                  │
│  └── has_before_triggers: BOOLEAN                                       │
└─────────────────────────────────────────────────────────────────────────┘
                               │
                               │ PARTITION OF
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│              pglogical.conflict_history_YYYY_MM                         │
│                    (Monthly Partition)                                  │
├─────────────────────────────────────────────────────────────────────────┤
│  Inherits all columns from parent                                       │
│  FOR VALUES FROM ('YYYY-MM-01') TO ('YYYY-MM+1-01')                    │
└─────────────────────────────────────────────────────────────────────────┘
```

## Entity: conflict_history

### Purpose
Stores replication conflict events for analysis, monitoring, and troubleshooting. Each record represents a single conflict detected and resolved by the apply worker.

### Table Definition

```sql
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

    -- Local tuple information
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
```

### Column Specifications

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| `id` | BIGSERIAL | NO | Unique identifier within partition |
| `recorded_at` | TIMESTAMPTZ | NO | When conflict was recorded (partition key) |
| `sub_id` | OID | NO | Subscription OID from `pglogical.subscription` |
| `sub_name` | NAME | YES | Subscription name (denormalized for queries) |
| `conflict_type` | TEXT | NO | Type of conflict detected |
| `resolution` | TEXT | NO | How the conflict was resolved |
| `schema_name` | NAME | NO | Schema containing the affected table |
| `table_name` | NAME | NO | Name of the affected table |
| `index_name` | NAME | YES | Index where conflict was detected |
| `local_tuple` | JSONB | YES | Local row data as JSONB |
| `local_xid` | XID | YES | Transaction ID that created local tuple |
| `local_origin` | INTEGER | YES | Replication origin of local tuple |
| `local_commit_ts` | TIMESTAMPTZ | YES | Commit timestamp of local tuple |
| `remote_tuple` | JSONB | YES | Remote row data as JSONB |
| `remote_origin` | INTEGER | NO | Replication origin of remote change |
| `remote_commit_ts` | TIMESTAMPTZ | NO | Commit timestamp on remote origin |
| `remote_commit_lsn` | PG_LSN | NO | LSN of remote commit |
| `has_before_triggers` | BOOLEAN | NO | Whether BEFORE triggers modified remote tuple |

### Conflict Types

| Value | Description | Has Local Tuple |
|-------|-------------|-----------------|
| `insert_insert` | INSERT conflicts with existing row | Yes |
| `update_update` | UPDATE conflicts with local modification | Yes |
| `update_delete` | UPDATE target not found (deleted locally) | No |
| `delete_delete` | DELETE target not found (deleted locally) | No |

### Resolution Types

| Value | Description |
|-------|-------------|
| `apply_remote` | Applied the remote change |
| `keep_local` | Kept the local version |
| `skip` | Skipped the operation |

### Indexes

```sql
-- Query by subscription
CREATE INDEX conflict_history_sub_id_idx
    ON pglogical.conflict_history (sub_id);

-- Query by affected table
CREATE INDEX conflict_history_relation_idx
    ON pglogical.conflict_history (schema_name, table_name);

-- Query by conflict type
CREATE INDEX conflict_history_type_idx
    ON pglogical.conflict_history (conflict_type);

-- Query by resolution
CREATE INDEX conflict_history_resolution_idx
    ON pglogical.conflict_history (resolution);
```

### Partitioning

**Strategy**: Monthly range partitions on `recorded_at`

**Naming Convention**: `conflict_history_YYYY_MM`

**Example**:
```sql
-- January 2025 partition
CREATE TABLE pglogical.conflict_history_2025_01
    PARTITION OF pglogical.conflict_history
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

-- February 2025 partition
CREATE TABLE pglogical.conflict_history_2025_02
    PARTITION OF pglogical.conflict_history
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
```

**Lifecycle**:
1. Partitions created on-demand by `conflict_history_ensure_partition()`
2. Old partitions dropped by `conflict_history_cleanup(retention_days)`

## Views

### recent_conflicts

Shows conflicts from the last 24 hours.

```sql
CREATE VIEW pglogical.recent_conflicts AS
SELECT *
FROM pglogical.conflict_history
WHERE recorded_at > now() - interval '24 hours'
ORDER BY recorded_at DESC;
```

### conflict_summary

Aggregated view of conflicts by table and type over last 7 days.

```sql
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

## JSONB Tuple Format

### Example local_tuple/remote_tuple Structure

```json
{
    "id": "42",
    "name": "example",
    "created_at": "2025-01-15 10:30:00+00",
    "data": "(unchanged-toast-datum)",
    "nullable_col": null
}
```

**Notes**:
- All values stored as strings (from type output functions)
- NULL SQL values represented as JSON null
- TOAST values not available stored as `"(unchanged-toast-datum)"`
- Values exceeding `conflict_history_max_tuple_size` are truncated

## Validation Rules

| Field | Validation |
|-------|------------|
| `conflict_type` | Must be one of: insert_insert, update_update, update_delete, delete_delete |
| `resolution` | Must be one of: apply_remote, keep_local, skip |
| `recorded_at` | Defaults to `clock_timestamp()`, cannot be NULL |
| `sub_id` | Must be valid OID (not validated by constraint) |
| `remote_origin` | Cannot be NULL |
| `remote_commit_ts` | Cannot be NULL |
| `remote_commit_lsn` | Cannot be NULL |

## Storage Estimates

| Scenario | Records/Day | Storage/Day | Storage/Month |
|----------|-------------|-------------|---------------|
| Low conflict rate | 10 | ~20 KB | ~600 KB |
| Normal conflict rate | 1,000 | ~2 MB | ~60 MB |
| High conflict rate | 100,000 | ~200 MB | ~6 GB |

**Assumptions**:
- ~2 KB per record without tuple data
- ~4 KB per record with tuple data
- Tuple storage disabled reduces size by ~50%

## Relationships

```
pglogical.subscription          pglogical.conflict_history
┌─────────────────────┐        ┌─────────────────────────┐
│ sub_id (PK)         │◄───────│ sub_id (FK - logical)   │
│ sub_name            │        │ sub_name (denormalized) │
└─────────────────────┘        └─────────────────────────┘

Note: No physical foreign key constraint to avoid blocking
      subscription drops. sub_id is a logical reference only.
```

## Migration Path

### Upgrade from 2.4.6 to 2.5.0

1. Schema created via `ALTER EXTENSION pglogical UPDATE`
2. Initial partition created for current month
3. No data migration needed (new table)
4. Feature disabled by default

### Downgrade from 2.5.0 to 2.4.6

1. Schema dropped via extension downgrade script
2. All conflict history data lost
3. Feature automatically disabled
