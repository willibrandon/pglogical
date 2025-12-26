# Feature Specification: Conflict History Persistence

**Feature Branch**: `001-conflict-history`
**Created**: 2025-12-25
**Status**: Draft
**Target Version**: pglogical 2.5.0+
**Input**: Add native conflict history persistence to pglogical. Instead of (or in addition to) logging conflicts via ereport(), persist conflict data to a queryable table within the apply worker process.

## Clarifications

### Session 2025-12-25

- Q: Who should have access to query conflict_history data (which may contain sensitive tuple data)? → A: Same permissions as other pglogical tables (accessible to replication/superuser roles)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Query Conflict History (Priority: P1)

As a database administrator, I need to query replication conflicts from a SQL table so that I can analyze conflict patterns, identify problematic tables, and troubleshoot replication issues without parsing server logs.

**Why this priority**: This is the core value proposition - enabling programmatic access to conflict data. Without queryable conflict history, administrators must manually parse logs which is error-prone and time-consuming.

**Independent Test**: Can be fully tested by enabling conflict history, creating a replication conflict scenario, and querying the conflict_history table to verify the conflict was recorded with all expected metadata.

**Acceptance Scenarios**:

1. **Given** conflict history is enabled and a replication conflict occurs, **When** I query `pglogical.conflict_history`, **Then** I see a record with conflict type, resolution, affected table, and timestamp
2. **Given** conflict history is enabled and multiple conflicts occur on different tables, **When** I query by schema_name and table_name, **Then** I can filter conflicts for specific tables
3. **Given** conflict history is enabled, **When** I query recent_conflicts view, **Then** I see conflicts from the last 24 hours ordered by most recent first
4. **Given** conflict history is disabled (default), **When** a conflict occurs, **Then** existing ereport() logging continues and no table record is created

---

### User Story 2 - Configure Conflict Recording (Priority: P1)

As a database administrator, I need to enable/disable conflict history recording and control what data is captured so that I can balance observability needs against storage and performance overhead.

**Why this priority**: Configuration is essential for adoption. Administrators must be able to enable the feature and tune it to their environment before they can use it.

**Independent Test**: Can be tested by setting GUC variables and verifying that conflict recording behavior changes accordingly (enabled/disabled, with/without tuple data).

**Acceptance Scenarios**:

1. **Given** default installation, **When** I check `pglogical.conflict_history_enabled`, **Then** it is OFF for backward compatibility
2. **Given** I set `pglogical.conflict_history_enabled = on`, **When** I reload configuration, **Then** subsequent conflicts are recorded to the table
3. **Given** I set `pglogical.conflict_history_store_tuples = off`, **When** a conflict occurs, **Then** the record contains metadata but local_tuple and remote_tuple are NULL
4. **Given** I set `pglogical.conflict_history_max_tuple_size = 256`, **When** a conflict involves a tuple with a field exceeding 256 bytes, **Then** that field value is truncated in the stored JSONB

---

### User Story 3 - View Conflict Statistics (Priority: P2)

As a database administrator, I need to see aggregate conflict statistics so that I can quickly assess replication health and identify trends without writing complex queries.

**Why this priority**: Aggregated views provide immediate value for monitoring but are secondary to having the raw data available for custom analysis.

**Independent Test**: Can be tested by generating several conflicts and calling `pglogical.conflict_stats()` to verify it returns correct counts and affected table counts.

**Acceptance Scenarios**:

1. **Given** conflicts exist in history, **When** I call `pglogical.conflict_stats()`, **Then** I receive total count, last 24h count, last hour count, and distinct tables affected
2. **Given** conflicts exist for a subscription, **When** I call `pglogical.show_subscription_conflicts(subscription_name)`, **Then** I see conflicts filtered by that subscription

---

### User Story 4 - Manage Conflict History Storage (Priority: P2)

As a database administrator, I need to manage conflict history storage through partitioning and retention policies so that the table doesn't grow unbounded and I can efficiently archive or purge old data.

**Why this priority**: Storage management is important for production use but not required for initial feature validation.

**Independent Test**: Can be tested by calling partition management functions and verifying partitions are created/dropped appropriately.

**Acceptance Scenarios**:

1. **Given** a new month begins, **When** I call `pglogical.conflict_history_ensure_partition(target_date)`, **Then** a new monthly partition is created if it doesn't exist
2. **Given** partitions older than 30 days exist, **When** I call `pglogical.conflict_history_cleanup(30)`, **Then** those old partitions are dropped and the function returns the count of dropped partitions
3. **Given** a conflict occurs, **When** the current month's partition doesn't exist, **Then** the system automatically creates it before inserting

---

### User Story 5 - Investigate Specific Conflicts (Priority: P3)

As a database administrator investigating a data discrepancy, I need to see the actual tuple values involved in a conflict so that I can understand what data was in conflict and verify the resolution was appropriate.

**Why this priority**: Detailed tuple inspection is an advanced use case for deep troubleshooting, not needed for basic conflict monitoring.

**Independent Test**: Can be tested by creating a conflict with known tuple values and verifying the local_tuple and remote_tuple JSONB columns contain the expected field values.

**Acceptance Scenarios**:

1. **Given** conflict history with tuple storage enabled, **When** I examine a conflict record, **Then** local_tuple shows the existing row's values as JSONB
2. **Given** conflict history with tuple storage enabled, **When** I examine a conflict record, **Then** remote_tuple shows the incoming change's values as JSONB
3. **Given** a tuple contains a TOAST value that wasn't fetched, **When** the conflict is recorded, **Then** that field shows "(unchanged-toast-datum)" instead of the actual value

---

### Edge Cases

- What happens when the conflict_history table or partition doesn't exist? (System should create partition automatically or log a warning without crashing the apply worker)
- What happens when SPI_connect fails during conflict recording? (Conflict should still be applied per resolution; recording failure should log a warning but not abort the transaction)
- What happens when tuple JSONB conversion fails due to unsupported types? (Should fall back to NULL or text representation with a warning, not abort)
- How does the system handle extremely high conflict rates? (Each conflict adds an INSERT within the transaction; very high rates may impact apply performance)
- What happens when disk is full and the INSERT fails? (Warning should be logged; apply should continue)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST persist conflict records to `pglogical.conflict_history` table when `pglogical.conflict_history_enabled` is ON
- **FR-002**: System MUST record conflict_type (insert_insert, update_update, update_delete, delete_delete) for each conflict
- **FR-003**: System MUST record resolution (apply_remote, keep_local, skip) for each conflict
- **FR-004**: System MUST record subscription context (sub_id, sub_name) for each conflict
- **FR-005**: System MUST record affected relation (schema_name, table_name) for each conflict
- **FR-006**: System MUST record timestamps (recorded_at, remote_commit_ts) for each conflict
- **FR-007**: System MUST record replication origin information (remote_origin, local_origin when available) for each conflict
- **FR-008**: System MUST optionally store local and remote tuple data as JSONB when `pglogical.conflict_history_store_tuples` is ON
- **FR-009**: System MUST truncate individual tuple field values exceeding `pglogical.conflict_history_max_tuple_size` bytes
- **FR-010**: System MUST continue normal ereport() logging regardless of conflict history setting (additive, not replacement)
- **FR-011**: System MUST use monthly partitioning for the conflict_history table (PARTITION BY RANGE on recorded_at)
- **FR-012**: System MUST provide a function to ensure partitions exist for a given date
- **FR-013**: System MUST provide a function to clean up partitions older than a specified retention period
- **FR-014**: System MUST provide a view showing conflicts from the last 24 hours
- **FR-015**: System MUST provide a view showing conflict summaries grouped by table and type
- **FR-016**: System MUST provide a function returning aggregate conflict statistics
- **FR-017**: System MUST NOT abort apply transactions if conflict history recording fails (graceful degradation)
- **FR-018**: System MUST default to conflict_history_enabled = OFF for backward compatibility
- **FR-019**: System MUST support configuration reload (PGC_SIGHUP) for all conflict history GUC variables
- **FR-020**: System MUST use the same permission model as other pglogical catalog tables for conflict_history access (replication roles and superusers)

### Key Entities

- **Conflict Record**: Represents a single replication conflict event. Contains: identity (id, recorded_at), subscription context (sub_id, sub_name), conflict classification (conflict_type, resolution), relation context (schema_name, table_name, index_name), local tuple state (local_tuple, local_xid, local_origin, local_commit_ts), remote tuple state (remote_tuple, remote_origin, remote_commit_ts, remote_commit_lsn), and flags (has_before_triggers)

- **Partition**: A monthly time-range partition of the conflict_history table. Named `conflict_history_YYYY_MM`. Enables efficient cleanup and archival of old conflict data.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Administrators can query conflicts by table, type, or time range in under 1 second for tables with up to 100,000 conflict records
- **SC-002**: Conflict history recording adds less than 5% overhead to apply worker transaction time under normal conflict rates (fewer than 100 conflicts per second)
- **SC-003**: Cleanup of a monthly partition completes in under 10 seconds regardless of partition size
- **SC-004**: Feature adoption: administrators can enable conflict history and see recorded conflicts within 5 minutes of configuration change
- **SC-005**: Storage is predictable: conflict records consume less than 2KB per record on average (excluding tuple data)
- **SC-006**: All existing pglogical functionality continues to work unchanged when conflict history is disabled (default state)
- **SC-007**: Partition management requires manual intervention at most once per month (or can be fully automated via pg_cron)

## Assumptions

- The apply worker has an active SPI connection available within the transaction context when conflicts are detected
- Monthly partitioning provides sufficient granularity for most retention policies (users wanting daily partitions would need customization)
- JSONB storage for tuple data is acceptable for conflict analysis use cases (exact binary representation not required)
- Users are expected to set up scheduled jobs (e.g., pg_cron) for automatic partition creation and cleanup
- The existing `pglogical_report_conflict()` function signature provides all necessary conflict context for recording
