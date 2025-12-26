# SQL Function Contracts: Conflict History

**Feature**: 001-conflict-history
**Date**: 2025-12-25

This document specifies the SQL function signatures, parameters, return types, and behaviors for the conflict history feature.

## Partition Management Functions

### conflict_history_ensure_partition

Ensures a partition exists for the specified date. Creates the partition if it doesn't exist.

```sql
CREATE FUNCTION pglogical.conflict_history_ensure_partition(
    target_date DATE DEFAULT CURRENT_DATE
) RETURNS VOID
```

**Parameters**:
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `target_date` | DATE | CURRENT_DATE | Date for which to ensure partition exists |

**Behavior**:
1. Calculates start/end of month containing `target_date`
2. Checks if partition `conflict_history_YYYY_MM` exists
3. If not exists, creates partition with appropriate range
4. If exists, no-op (idempotent)

**Errors**:
- None expected (CREATE TABLE IF NOT EXISTS semantics)

**Example**:
```sql
-- Ensure current month's partition exists
SELECT pglogical.conflict_history_ensure_partition();

-- Pre-create next month's partition
SELECT pglogical.conflict_history_ensure_partition(CURRENT_DATE + interval '1 month');
```

---

### conflict_history_cleanup

Drops partitions older than the specified retention period.

```sql
CREATE FUNCTION pglogical.conflict_history_cleanup(
    retention_days INTEGER DEFAULT 30
) RETURNS INTEGER
```

**Parameters**:
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `retention_days` | INTEGER | 30 | Days to retain conflict history |

**Returns**: Number of partitions dropped

**Behavior**:
1. Queries `pg_inherits` for child tables of `conflict_history`
2. Parses partition names to extract dates
3. Drops partitions where month end < (current date - retention_days)
4. Returns count of dropped partitions

**Errors**:
- None expected (DROP TABLE IF EXISTS semantics per partition)

**Example**:
```sql
-- Cleanup with default 30-day retention
SELECT pglogical.conflict_history_cleanup();
-- Returns: 2 (e.g., dropped 2 old partitions)

-- Cleanup with 90-day retention
SELECT pglogical.conflict_history_cleanup(90);

-- Cleanup all old data (keep only current month)
SELECT pglogical.conflict_history_cleanup(0);
```

---

## Query Functions

### conflict_stats

Returns aggregate statistics about recorded conflicts.

```sql
CREATE FUNCTION pglogical.conflict_stats(
    OUT total_conflicts BIGINT,
    OUT last_24h BIGINT,
    OUT last_hour BIGINT,
    OUT tables_affected BIGINT
) RETURNS RECORD
```

**Returns**:
| Column | Type | Description |
|--------|------|-------------|
| `total_conflicts` | BIGINT | Total conflicts in history |
| `last_24h` | BIGINT | Conflicts in last 24 hours |
| `last_hour` | BIGINT | Conflicts in last hour |
| `tables_affected` | BIGINT | Distinct tables with conflicts |

**Behavior**:
- Queries `conflict_history` for aggregate counts
- Returns single record with statistics
- Stable function (can be used in queries)

**Example**:
```sql
SELECT * FROM pglogical.conflict_stats();
-- Returns:
--  total_conflicts | last_24h | last_hour | tables_affected
-- -----------------+----------+-----------+-----------------
--             1523 |       42 |         3 |              12
```

---

### show_subscription_conflicts

Returns conflicts for a specific subscription.

```sql
CREATE FUNCTION pglogical.show_subscription_conflicts(
    subscription_name NAME,
    since TIMESTAMPTZ DEFAULT now() - interval '24 hours',
    max_rows INTEGER DEFAULT 100
) RETURNS SETOF pglogical.conflict_history
```

**Parameters**:
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `subscription_name` | NAME | (required) | Subscription to query |
| `since` | TIMESTAMPTZ | now() - 24h | Start of time range |
| `max_rows` | INTEGER | 100 | Maximum rows to return |

**Returns**: Set of `conflict_history` records

**Behavior**:
1. Joins `conflict_history` with `subscription` on sub_id
2. Filters by subscription name and time range
3. Orders by `recorded_at` DESC
4. Limits to `max_rows`

**Errors**:
- Returns empty set if subscription not found

**Example**:
```sql
-- Get last 24h conflicts for a subscription
SELECT * FROM pglogical.show_subscription_conflicts('my_subscription');

-- Get last week's conflicts, up to 500 rows
SELECT * FROM pglogical.show_subscription_conflicts(
    'my_subscription',
    now() - interval '7 days',
    500
);
```

---

## GUC Variables

These are not SQL functions but configuration parameters accessible via `SET`/`SHOW`.

### pglogical.conflict_history_enabled

```sql
-- Type: boolean
-- Default: false
-- Context: PGC_SIGHUP (reloadable)

SET pglogical.conflict_history_enabled = on;
SHOW pglogical.conflict_history_enabled;
```

### pglogical.conflict_history_store_tuples

```sql
-- Type: boolean
-- Default: true
-- Context: PGC_SIGHUP (reloadable)

SET pglogical.conflict_history_store_tuples = off;
SHOW pglogical.conflict_history_store_tuples;
```

### pglogical.conflict_history_max_tuple_size

```sql
-- Type: integer
-- Default: 1024
-- Range: 64 - 65536
-- Context: PGC_SIGHUP (reloadable)

SET pglogical.conflict_history_max_tuple_size = 2048;
SHOW pglogical.conflict_history_max_tuple_size;
```

---

## Views

### recent_conflicts

```sql
-- Read-only view of last 24 hours
SELECT * FROM pglogical.recent_conflicts;
```

**Columns**: All columns from `conflict_history`
**Filter**: `recorded_at > now() - interval '24 hours'`
**Order**: `recorded_at DESC`

### conflict_summary

```sql
-- Aggregated view of last 7 days
SELECT * FROM pglogical.conflict_summary;
```

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `schema_name` | NAME | Schema name |
| `table_name` | NAME | Table name |
| `conflict_type` | TEXT | Type of conflict |
| `resolution` | TEXT | Resolution applied |
| `conflict_count` | BIGINT | Number of conflicts |
| `first_seen` | TIMESTAMPTZ | Earliest conflict |
| `last_seen` | TIMESTAMPTZ | Latest conflict |

**Filter**: `recorded_at > now() - interval '7 days'`
**Grouping**: `schema_name, table_name, conflict_type, resolution`
**Order**: `conflict_count DESC`

---

## Error Handling

All functions follow these conventions:

1. **Partition functions**: Silent success/no-op if already exists/nothing to do
2. **Query functions**: Return empty results if no data matches criteria
3. **No exceptions**: Functions designed to never throw under normal conditions
4. **Permission errors**: Follow standard PostgreSQL permission model (superuser/replication roles)

## Permissions

All objects inherit permissions from the `pglogical` schema:
- Superusers: Full access
- Replication roles: Full access
- Regular users: No access by default

```sql
-- Grant access to a specific role if needed
GRANT SELECT ON pglogical.conflict_history TO monitoring_role;
GRANT SELECT ON pglogical.recent_conflicts TO monitoring_role;
GRANT SELECT ON pglogical.conflict_summary TO monitoring_role;
GRANT EXECUTE ON FUNCTION pglogical.conflict_stats() TO monitoring_role;
```
