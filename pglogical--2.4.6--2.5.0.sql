-- Upgrade script for pglogical 2.4.6 to 2.5.0
-- Adds conflict history persistence feature

-- ============================================================================
-- Conflict History Table (Partitioned)
-- ============================================================================

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

COMMENT ON TABLE pglogical.conflict_history IS
    'Records replication conflicts detected by the apply worker for analysis and monitoring';

COMMENT ON COLUMN pglogical.conflict_history.id IS
    'Unique identifier within partition';
COMMENT ON COLUMN pglogical.conflict_history.recorded_at IS
    'When conflict was recorded (partition key)';
COMMENT ON COLUMN pglogical.conflict_history.sub_id IS
    'Subscription OID from pglogical.subscription';
COMMENT ON COLUMN pglogical.conflict_history.sub_name IS
    'Subscription name (denormalized for queries)';
COMMENT ON COLUMN pglogical.conflict_history.conflict_type IS
    'Type of conflict: insert_insert, update_update, update_delete, delete_delete';
COMMENT ON COLUMN pglogical.conflict_history.resolution IS
    'How conflict was resolved: apply_remote, keep_local, skip';
COMMENT ON COLUMN pglogical.conflict_history.schema_name IS
    'Schema containing the affected table';
COMMENT ON COLUMN pglogical.conflict_history.table_name IS
    'Name of the affected table';
COMMENT ON COLUMN pglogical.conflict_history.index_name IS
    'Index where conflict was detected';
COMMENT ON COLUMN pglogical.conflict_history.local_tuple IS
    'Local row data as JSONB (if tuple storage enabled)';
COMMENT ON COLUMN pglogical.conflict_history.local_xid IS
    'Transaction ID that created local tuple';
COMMENT ON COLUMN pglogical.conflict_history.local_origin IS
    'Replication origin of local tuple';
COMMENT ON COLUMN pglogical.conflict_history.local_commit_ts IS
    'Commit timestamp of local tuple';
COMMENT ON COLUMN pglogical.conflict_history.remote_tuple IS
    'Remote row data as JSONB (if tuple storage enabled)';
COMMENT ON COLUMN pglogical.conflict_history.remote_origin IS
    'Replication origin of remote change';
COMMENT ON COLUMN pglogical.conflict_history.remote_commit_ts IS
    'Commit timestamp on remote origin';
COMMENT ON COLUMN pglogical.conflict_history.remote_commit_lsn IS
    'LSN of remote commit';
COMMENT ON COLUMN pglogical.conflict_history.has_before_triggers IS
    'Whether BEFORE triggers modified remote tuple';

-- ============================================================================
-- Indexes
-- ============================================================================

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

-- ============================================================================
-- Partition Management Functions
-- ============================================================================

CREATE OR REPLACE FUNCTION pglogical.conflict_history_ensure_partition(
    target_date DATE DEFAULT CURRENT_DATE
) RETURNS VOID AS $$
DECLARE
    partition_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    -- Calculate month boundaries
    start_date := date_trunc('month', target_date)::DATE;
    end_date := (date_trunc('month', target_date) + interval '1 month')::DATE;

    -- Generate partition name
    partition_name := 'conflict_history_' || to_char(target_date, 'YYYY_MM');

    -- Check if partition already exists
    IF NOT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'pglogical'
        AND c.relname = partition_name
    ) THEN
        -- Create the partition
        EXECUTE format(
            'CREATE TABLE pglogical.%I PARTITION OF pglogical.conflict_history
             FOR VALUES FROM (%L) TO (%L)',
            partition_name, start_date, end_date
        );
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pglogical.conflict_history_ensure_partition(DATE) IS
    'Ensures a partition exists for the specified date. Creates the partition if it does not exist.';

CREATE OR REPLACE FUNCTION pglogical.conflict_history_cleanup(
    retention_days INTEGER DEFAULT 30
) RETURNS INTEGER AS $$
DECLARE
    partition_rec RECORD;
    dropped_count INTEGER := 0;
    cutoff_date DATE;
    partition_end_date DATE;
BEGIN
    -- Calculate cutoff date
    cutoff_date := CURRENT_DATE - retention_days;

    -- Find and drop old partitions
    FOR partition_rec IN
        SELECT c.relname, c.oid
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_inherits i ON i.inhrelid = c.oid
        JOIN pg_class parent ON parent.oid = i.inhparent
        WHERE n.nspname = 'pglogical'
        AND parent.relname = 'conflict_history'
        AND c.relname ~ '^conflict_history_[0-9]{4}_[0-9]{2}$'
    LOOP
        -- Parse the date from partition name (format: conflict_history_YYYY_MM)
        partition_end_date := to_date(
            substring(partition_rec.relname from 'conflict_history_([0-9]{4}_[0-9]{2})'),
            'YYYY_MM'
        ) + interval '1 month';

        -- Drop if partition's month end is before cutoff
        IF partition_end_date <= cutoff_date THEN
            EXECUTE format('DROP TABLE pglogical.%I', partition_rec.relname);
            dropped_count := dropped_count + 1;
        END IF;
    END LOOP;

    RETURN dropped_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pglogical.conflict_history_cleanup(INTEGER) IS
    'Drops conflict_history partitions older than the specified retention period. Returns number of partitions dropped.';

-- ============================================================================
-- Create Initial Partition for Current Month
-- ============================================================================

SELECT pglogical.conflict_history_ensure_partition(CURRENT_DATE);

-- ============================================================================
-- Views
-- ============================================================================

CREATE VIEW pglogical.recent_conflicts AS
SELECT *
FROM pglogical.conflict_history
WHERE recorded_at > now() - interval '24 hours'
ORDER BY recorded_at DESC;

COMMENT ON VIEW pglogical.recent_conflicts IS
    'Shows conflicts recorded in the last 24 hours';

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

COMMENT ON VIEW pglogical.conflict_summary IS
    'Aggregated view of conflicts by table and type over last 7 days';

-- ============================================================================
-- Statistics Functions
-- ============================================================================

CREATE OR REPLACE FUNCTION pglogical.conflict_stats(
    OUT total_conflicts BIGINT,
    OUT last_24h BIGINT,
    OUT last_hour BIGINT,
    OUT tables_affected BIGINT
) RETURNS RECORD AS $$
BEGIN
    SELECT count(*) INTO total_conflicts
    FROM pglogical.conflict_history;

    SELECT count(*) INTO last_24h
    FROM pglogical.conflict_history
    WHERE recorded_at > now() - interval '24 hours';

    SELECT count(*) INTO last_hour
    FROM pglogical.conflict_history
    WHERE recorded_at > now() - interval '1 hour';

    SELECT count(DISTINCT (schema_name, table_name)) INTO tables_affected
    FROM pglogical.conflict_history;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pglogical.conflict_stats() IS
    'Returns aggregate statistics about recorded conflicts';

CREATE OR REPLACE FUNCTION pglogical.show_subscription_conflicts(
    subscription_name NAME,
    since TIMESTAMPTZ DEFAULT now() - interval '24 hours',
    max_rows INTEGER DEFAULT 100
) RETURNS SETOF pglogical.conflict_history AS $$
BEGIN
    RETURN QUERY
    SELECT ch.*
    FROM pglogical.conflict_history ch
    WHERE ch.sub_name = subscription_name
    AND ch.recorded_at >= since
    ORDER BY ch.recorded_at DESC
    LIMIT max_rows;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pglogical.show_subscription_conflicts(NAME, TIMESTAMPTZ, INTEGER) IS
    'Returns conflicts for a specific subscription within the given time range';
