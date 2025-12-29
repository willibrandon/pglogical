\echo Use "CREATE EXTENSION pglogical" to load this file. \quit

CREATE TABLE pglogical.node (
    node_id oid NOT NULL PRIMARY KEY,
    node_name name NOT NULL UNIQUE
) WITH (user_catalog_table=true);

CREATE TABLE pglogical.node_interface (
    if_id oid NOT NULL PRIMARY KEY,
    if_name name NOT NULL, -- default same as node name
    if_nodeid oid REFERENCES node(node_id),
    if_dsn text NOT NULL,
    UNIQUE (if_nodeid, if_name)
);

CREATE TABLE pglogical.local_node (
    node_id oid PRIMARY KEY REFERENCES node(node_id),
    node_local_interface oid NOT NULL REFERENCES node_interface(if_id)
);

CREATE TABLE pglogical.subscription (
    sub_id oid NOT NULL PRIMARY KEY,
    sub_name name NOT NULL UNIQUE,
    sub_origin oid NOT NULL REFERENCES node(node_id),
    sub_target oid NOT NULL REFERENCES node(node_id),
    sub_origin_if oid NOT NULL REFERENCES node_interface(if_id),
    sub_target_if oid NOT NULL REFERENCES node_interface(if_id),
    sub_enabled boolean NOT NULL DEFAULT true,
    sub_slot_name name NOT NULL,
    sub_replication_sets text[],
    sub_forward_origins text[],
    sub_apply_delay interval NOT NULL DEFAULT '0',
    sub_force_text_transfer boolean NOT NULL DEFAULT 'f'
);

CREATE TABLE pglogical.local_sync_status (
    sync_kind "char" NOT NULL CHECK (sync_kind IN ('i', 's', 'd', 'f')),
    sync_subid oid NOT NULL REFERENCES pglogical.subscription(sub_id),
    sync_nspname name,
    sync_relname name,
    sync_status "char" NOT NULL,
	sync_statuslsn pg_lsn NOT NULL,
    UNIQUE (sync_subid, sync_nspname, sync_relname)
);


CREATE FUNCTION pglogical.create_node(node_name name, dsn text)
RETURNS oid STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_create_node';
CREATE FUNCTION pglogical.drop_node(node_name name, ifexists boolean DEFAULT false)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_drop_node';

CREATE FUNCTION pglogical.alter_node_add_interface(node_name name, interface_name name, dsn text)
RETURNS oid STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_alter_node_add_interface';
CREATE FUNCTION pglogical.alter_node_drop_interface(node_name name, interface_name name)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_alter_node_drop_interface';

CREATE FUNCTION pglogical.create_subscription(subscription_name name, provider_dsn text,
    replication_sets text[] = '{default,default_insert_only,ddl_sql}', synchronize_structure boolean = false,
    synchronize_data boolean = true, forward_origins text[] = '{all}', apply_delay interval DEFAULT '0',
    force_text_transfer boolean = false)
RETURNS oid STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_create_subscription';
CREATE FUNCTION pglogical.drop_subscription(subscription_name name, ifexists boolean DEFAULT false)
RETURNS oid STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_drop_subscription';

CREATE FUNCTION pglogical.alter_subscription_interface(subscription_name name, interface_name name)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_alter_subscription_interface';

CREATE FUNCTION pglogical.alter_subscription_disable(subscription_name name, immediate boolean DEFAULT false)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_alter_subscription_disable';
CREATE FUNCTION pglogical.alter_subscription_enable(subscription_name name, immediate boolean DEFAULT false)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_alter_subscription_enable';

CREATE FUNCTION pglogical.alter_subscription_add_replication_set(subscription_name name, replication_set name)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_alter_subscription_add_replication_set';
CREATE FUNCTION pglogical.alter_subscription_remove_replication_set(subscription_name name, replication_set name)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_alter_subscription_remove_replication_set';

CREATE FUNCTION pglogical.show_subscription_status(subscription_name name DEFAULT NULL,
    OUT subscription_name text, OUT status text, OUT provider_node text,
    OUT provider_dsn text, OUT slot_name text, OUT replication_sets text[],
    OUT forward_origins text[])
RETURNS SETOF record STABLE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_show_subscription_status';

CREATE TABLE pglogical.replication_set (
    set_id oid NOT NULL PRIMARY KEY,
    set_nodeid oid NOT NULL,
    set_name name NOT NULL,
    replicate_insert boolean NOT NULL DEFAULT true,
    replicate_update boolean NOT NULL DEFAULT true,
    replicate_delete boolean NOT NULL DEFAULT true,
    replicate_truncate boolean NOT NULL DEFAULT true,
    UNIQUE (set_nodeid, set_name)
) WITH (user_catalog_table=true);

CREATE TABLE pglogical.replication_set_table (
    set_id oid NOT NULL,
    set_reloid regclass NOT NULL,
    set_att_list text[],
    set_row_filter pg_node_tree,
    PRIMARY KEY(set_id, set_reloid)
) WITH (user_catalog_table=true);

CREATE TABLE pglogical.replication_set_seq (
    set_id oid NOT NULL,
    set_seqoid regclass NOT NULL,
    PRIMARY KEY(set_id, set_seqoid)
) WITH (user_catalog_table=true);

CREATE TABLE pglogical.sequence_state (
	seqoid oid NOT NULL PRIMARY KEY,
	cache_size integer NOT NULL,
	last_value bigint NOT NULL
) WITH (user_catalog_table=true);

CREATE TABLE pglogical.depend (
    classid oid NOT NULL,
    objid oid NOT NULL,
    objsubid integer NOT NULL,

    refclassid oid NOT NULL,
    refobjid oid NOT NULL,
    refobjsubid integer NOT NULL,

	deptype "char" NOT NULL
) WITH (user_catalog_table=true);

CREATE VIEW pglogical.TABLES AS
    WITH set_relations AS (
        SELECT s.set_name, r.set_reloid
          FROM pglogical.replication_set_table r,
               pglogical.replication_set s,
               pglogical.local_node n
         WHERE s.set_nodeid = n.node_id
           AND s.set_id = r.set_id
    ),
    user_tables AS (
        SELECT r.oid, n.nspname, r.relname, r.relreplident
          FROM pg_catalog.pg_class r,
               pg_catalog.pg_namespace n
         WHERE r.relkind = 'r'
           AND r.relpersistence = 'p'
           AND n.oid = r.relnamespace
           AND n.nspname !~ '^pg_'
           AND n.nspname != 'information_schema'
           AND n.nspname != 'pglogical'
    )
    SELECT r.oid AS relid, n.nspname, r.relname, s.set_name
      FROM pg_catalog.pg_namespace n,
           pg_catalog.pg_class r,
           set_relations s
     WHERE r.relkind = 'r'
       AND n.oid = r.relnamespace
       AND r.oid = s.set_reloid
     UNION
    SELECT t.oid AS relid, t.nspname, t.relname, NULL
      FROM user_tables t
     WHERE t.oid NOT IN (SELECT set_reloid FROM set_relations);

CREATE FUNCTION pglogical.create_replication_set(set_name name,
    replicate_insert boolean = true, replicate_update boolean = true,
    replicate_delete boolean = true, replicate_truncate boolean = true)
RETURNS oid STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_create_replication_set';
CREATE FUNCTION pglogical.alter_replication_set(set_name name,
    replicate_insert boolean DEFAULT NULL, replicate_update boolean DEFAULT NULL,
    replicate_delete boolean DEFAULT NULL, replicate_truncate boolean DEFAULT NULL)
RETURNS oid CALLED ON NULL INPUT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_alter_replication_set';
CREATE FUNCTION pglogical.drop_replication_set(set_name name, ifexists boolean DEFAULT false)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_drop_replication_set';

CREATE FUNCTION pglogical.replication_set_add_table(set_name name, relation regclass, synchronize_data boolean DEFAULT false,
	columns text[] DEFAULT NULL, row_filter text DEFAULT NULL)
RETURNS boolean CALLED ON NULL INPUT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_replication_set_add_table';
CREATE FUNCTION pglogical.replication_set_add_all_tables(set_name name, schema_names text[], synchronize_data boolean DEFAULT false)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_replication_set_add_all_tables';
CREATE FUNCTION pglogical.replication_set_remove_table(set_name name, relation regclass)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_replication_set_remove_table';

CREATE FUNCTION pglogical.replication_set_add_sequence(set_name name, relation regclass, synchronize_data boolean DEFAULT false)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_replication_set_add_sequence';
CREATE FUNCTION pglogical.replication_set_add_all_sequences(set_name name, schema_names text[], synchronize_data boolean DEFAULT false)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_replication_set_add_all_sequences';
CREATE FUNCTION pglogical.replication_set_remove_sequence(set_name name, relation regclass)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_replication_set_remove_sequence';

CREATE FUNCTION pglogical.alter_subscription_synchronize(subscription_name name, truncate boolean DEFAULT false)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_alter_subscription_synchronize';

CREATE FUNCTION pglogical.alter_subscription_resynchronize_table(subscription_name name, relation regclass,
	truncate boolean DEFAULT true)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_alter_subscription_resynchronize_table';

CREATE FUNCTION pglogical.synchronize_sequence(relation regclass)
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_synchronize_sequence';

CREATE FUNCTION pglogical.table_data_filtered(reltyp anyelement, relation regclass, repsets text[])
RETURNS SETOF anyelement CALLED ON NULL INPUT STABLE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_table_data_filtered';

CREATE FUNCTION pglogical.show_repset_table_info(relation regclass, repsets text[], OUT relid oid, OUT nspname text,
	OUT relname text, OUT att_list text[], OUT has_row_filter boolean)
RETURNS record STRICT STABLE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_show_repset_table_info';

CREATE FUNCTION pglogical.show_subscription_table(subscription_name name, relation regclass, OUT nspname text, OUT relname text, OUT status text)
RETURNS record STRICT STABLE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_show_subscription_table';

CREATE TABLE pglogical.queue (
    queued_at timestamp with time zone NOT NULL,
    role name NOT NULL,
    replication_sets text[],
    message_type "char" NOT NULL,
    message json NOT NULL
);

CREATE FUNCTION pglogical.replicate_ddl_command(command text, replication_sets text[] DEFAULT '{ddl_sql}')
RETURNS boolean STRICT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_replicate_ddl_command';

CREATE OR REPLACE FUNCTION pglogical.queue_truncate()
RETURNS trigger LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_queue_truncate';

CREATE FUNCTION pglogical.pglogical_node_info(OUT node_id oid, OUT node_name text, OUT sysid text, OUT dbname text, OUT replication_sets text)
RETURNS record
STABLE STRICT LANGUAGE c AS 'MODULE_PATHNAME';

CREATE FUNCTION pglogical.pglogical_gen_slot_name(name, name, name)
RETURNS name
IMMUTABLE STRICT LANGUAGE c AS 'MODULE_PATHNAME';

CREATE FUNCTION pglogical_version() RETURNS text
LANGUAGE c AS 'MODULE_PATHNAME';

CREATE FUNCTION pglogical_version_num() RETURNS integer
LANGUAGE c AS 'MODULE_PATHNAME';

CREATE FUNCTION pglogical_max_proto_version() RETURNS integer
LANGUAGE c AS 'MODULE_PATHNAME';

CREATE FUNCTION pglogical_min_proto_version() RETURNS integer
LANGUAGE c AS 'MODULE_PATHNAME';

CREATE FUNCTION
pglogical.wait_slot_confirm_lsn(slotname name, target pg_lsn)
RETURNS void LANGUAGE c AS 'pglogical','pglogical_wait_slot_confirm_lsn';
CREATE FUNCTION pglogical.wait_for_subscription_sync_complete(subscription_name name)
RETURNS void RETURNS NULL ON NULL INPUT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_wait_for_subscription_sync_complete';

CREATE FUNCTION pglogical.wait_for_table_sync_complete(subscription_name name, relation regclass)
RETURNS void RETURNS NULL ON NULL INPUT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_wait_for_table_sync_complete';

CREATE FUNCTION pglogical.xact_commit_timestamp_origin("xid" xid, OUT "timestamp" timestamptz, OUT "roident" oid)
RETURNS record RETURNS NULL ON NULL INPUT VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_xact_commit_timestamp_origin';
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
