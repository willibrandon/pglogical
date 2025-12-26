# Quickstart: Conflict History

**Feature**: 001-conflict-history
**Date**: 2025-12-25

This guide walks through enabling and using the conflict history feature after implementation.

## Prerequisites

- pglogical 2.5.0+ installed
- Active replication subscription
- PostgreSQL 10+ (for declarative partitioning)

## Step 1: Upgrade Extension

If upgrading from an earlier version:

```sql
ALTER EXTENSION pglogical UPDATE;
```

This creates the `conflict_history` table, views, and management functions.

## Step 2: Enable Conflict History

Enable conflict history recording:

```sql
-- Enable on subscriber node
ALTER SYSTEM SET pglogical.conflict_history_enabled = on;
SELECT pg_reload_conf();
```

Verify the setting:

```sql
SHOW pglogical.conflict_history_enabled;
-- Returns: on
```

## Step 3: Configure Options (Optional)

### Disable Tuple Storage

To save space, disable storing actual tuple data:

```sql
ALTER SYSTEM SET pglogical.conflict_history_store_tuples = off;
SELECT pg_reload_conf();
```

### Adjust Tuple Truncation

Set maximum bytes per tuple field (default: 1024):

```sql
ALTER SYSTEM SET pglogical.conflict_history_max_tuple_size = 2048;
SELECT pg_reload_conf();
```

## Step 4: Generate Test Conflicts

Create a conflict scenario (on a bidirectional setup):

```sql
-- On provider: Insert row
INSERT INTO test_table (id, data) VALUES (1, 'provider');

-- On subscriber (before replication): Insert same key
INSERT INTO test_table (id, data) VALUES (1, 'subscriber');

-- Conflict will be detected and resolved based on pglogical.conflict_resolution
```

## Step 5: Query Conflict History

### View Recent Conflicts

```sql
-- Last 24 hours
SELECT * FROM pglogical.recent_conflicts;

-- Specific fields
SELECT
    recorded_at,
    conflict_type,
    resolution,
    schema_name || '.' || table_name AS relation,
    local_tuple->>'id' AS local_id,
    remote_tuple->>'id' AS remote_id
FROM pglogical.conflict_history
WHERE recorded_at > now() - interval '1 hour'
ORDER BY recorded_at DESC;
```

### Get Statistics

```sql
SELECT * FROM pglogical.conflict_stats();
-- Returns: total_conflicts, last_24h, last_hour, tables_affected
```

### View Summary by Table

```sql
SELECT * FROM pglogical.conflict_summary;
```

### Query Specific Subscription

```sql
SELECT * FROM pglogical.show_subscription_conflicts('my_subscription');
```

## Step 6: Set Up Partition Maintenance

### Manual Partition Creation

Pre-create next month's partition:

```sql
SELECT pglogical.conflict_history_ensure_partition(CURRENT_DATE + interval '1 month');
```

### Manual Cleanup

Remove partitions older than 30 days:

```sql
SELECT pglogical.conflict_history_cleanup(30);
-- Returns: number of dropped partitions
```

### Automated with pg_cron (Recommended)

```sql
-- Install pg_cron extension if not present
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule partition creation (1st of each month at midnight)
SELECT cron.schedule(
    'conflict_history_partition',
    '0 0 1 * *',
    $$SELECT pglogical.conflict_history_ensure_partition(CURRENT_DATE + interval '1 month')$$
);

-- Schedule cleanup (weekly on Sunday at 2am)
SELECT cron.schedule(
    'conflict_history_cleanup',
    '0 2 * * 0',
    $$SELECT pglogical.conflict_history_cleanup(30)$$
);
```

## Common Queries

### Find Most Conflicting Tables

```sql
SELECT
    schema_name,
    table_name,
    count(*) AS conflict_count
FROM pglogical.conflict_history
WHERE recorded_at > now() - interval '7 days'
GROUP BY schema_name, table_name
ORDER BY conflict_count DESC
LIMIT 10;
```

### Track Conflict Trends

```sql
SELECT
    date_trunc('hour', recorded_at) AS hour,
    count(*) AS conflicts
FROM pglogical.conflict_history
WHERE recorded_at > now() - interval '24 hours'
GROUP BY hour
ORDER BY hour;
```

### Analyze Resolution Patterns

```sql
SELECT
    conflict_type,
    resolution,
    count(*) AS occurrences
FROM pglogical.conflict_history
WHERE recorded_at > now() - interval '7 days'
GROUP BY conflict_type, resolution
ORDER BY occurrences DESC;
```

### Inspect Specific Conflict

```sql
SELECT
    recorded_at,
    conflict_type,
    resolution,
    local_tuple,
    remote_tuple,
    index_name
FROM pglogical.conflict_history
WHERE id = 12345;
```

## Verification Checklist

After enabling conflict history:

- [ ] `SHOW pglogical.conflict_history_enabled` returns `on`
- [ ] `SELECT count(*) FROM pglogical.conflict_history` works (may be 0)
- [ ] Creating a conflict scenario results in a new record
- [ ] `pglogical.conflict_stats()` returns valid data
- [ ] `pglogical.recent_conflicts` view works
- [ ] Partition creation function works
- [ ] Cleanup function works (on test partitions)

## Troubleshooting

### No Conflicts Being Recorded

1. Verify feature is enabled:
   ```sql
   SHOW pglogical.conflict_history_enabled;
   ```

2. Check for conflicts in server log (ereport still works)

3. Verify subscription is active:
   ```sql
   SELECT * FROM pglogical.show_subscription_status();
   ```

### Missing Partition Errors

If you see "no partition of relation" errors:

```sql
SELECT pglogical.conflict_history_ensure_partition(CURRENT_DATE);
```

### Storage Growing Too Fast

1. Reduce retention period:
   ```sql
   SELECT pglogical.conflict_history_cleanup(7);  -- Keep only 7 days
   ```

2. Disable tuple storage:
   ```sql
   ALTER SYSTEM SET pglogical.conflict_history_store_tuples = off;
   SELECT pg_reload_conf();
   ```

3. Reduce max tuple size:
   ```sql
   ALTER SYSTEM SET pglogical.conflict_history_max_tuple_size = 256;
   SELECT pg_reload_conf();
   ```

### Performance Impact

If apply worker is slow:

1. Verify conflict rate isn't excessive (> 100/sec may impact performance)
2. Consider disabling tuple storage
3. Monitor partition count (too many may slow queries)

## Disabling the Feature

To completely disable conflict history:

```sql
ALTER SYSTEM SET pglogical.conflict_history_enabled = off;
SELECT pg_reload_conf();
```

Note: Existing data remains in the table. To remove:

```sql
-- Remove all old partitions
SELECT pglogical.conflict_history_cleanup(0);
```
