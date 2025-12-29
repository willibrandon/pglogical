# Research: Conflict History Persistence

**Feature**: 001-conflict-history
**Date**: 2025-12-25

## Summary

This document consolidates research findings for implementing conflict history persistence in pglogical. The feature adds a queryable `pglogical.conflict_history` table that records replication conflicts directly from the apply worker.

## Technical Decisions

### 1. Tuple-to-JSONB Conversion

**Decision**: Use PostgreSQL's native JSONB construction APIs (`pushJsonbValue`, `JsonbValueToJsonb`).

**Rationale**:
- JSONB is queryable and indexable
- Native APIs available since PG 9.4+
- Existing pattern in pglogical_queue.c demonstrates feasibility
- Allows field-level truncation for storage management

**Alternatives Considered**:
- TEXT/HSTORE: Less queryable, no native indexing
- Bytea: Not human-readable, harder to analyze
- row_to_json(): SQL-level only, not available in C apply worker context

**Implementation Pattern**:
```c
JsonbParseState *state = NULL;
pushJsonbValue(&state, WJB_BEGIN_OBJECT, NULL);
// For each attribute: push key, push value
pushJsonbValue(&state, WJB_END_OBJECT, NULL);
return JsonbPGetDatum(JsonbValueToJsonb(result));
```

**Version Compatibility**:
- `DatumGetJsonb` macro changed in PG 11+ (handled via compat headers)
- All JSONB APIs stable across PG 9.4-18+

### 2. SPI Error Handling for Graceful Degradation

**Decision**: Use `PG_TRY`/`PG_CATCH` with `FlushErrorState()` for fire-and-forget recording.

**Rationale**:
- Recording failure MUST NOT abort the apply transaction (FR-017)
- Pattern proven in pglogical_functions.c (slot cleanup)
- Allows logging warning without stopping replication

**Implementation Pattern**:
```c
PG_TRY();
{
    SPI_connect();
    SPI_execute_with_args(insert_sql, ...);
    SPI_finish();
}
PG_CATCH();
{
    FlushErrorState();
    elog(WARNING, "conflict_history recording failed, continuing");
}
PG_END_TRY();
```

**Alternatives Considered**:
- Internal subtransactions: Added complexity, not needed for simple INSERT
- Abort on failure: Violates FR-017, would stop replication
- Background worker queue: Unnecessary complexity, apply worker has SPI access

### 3. Table Partitioning Strategy

**Decision**: Use declarative PARTITION BY RANGE on `recorded_at` with monthly granularity.

**Rationale**:
- Native PG 10+ partitioning is simpler and more efficient
- Monthly partitions balance granularity vs. management overhead
- Enables fast partition drops for retention cleanup
- Query optimizer automatically prunes irrelevant partitions

**Partition Naming Convention**: `conflict_history_YYYY_MM`
- Lexicographically sortable
- Easy to parse for retention cleanup
- PostgreSQL identifier-safe

**Version Compatibility**:
- PG 10+: Native PARTITION BY RANGE
- PG 9.4-9.6: Would require inheritance-based approach (not implemented; feature targets modern PG)

**Implementation Pattern**:
```sql
CREATE TABLE pglogical.conflict_history (...) PARTITION BY RANGE (recorded_at);

CREATE TABLE pglogical.conflict_history_2025_01
    PARTITION OF pglogical.conflict_history
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
```

### 4. GUC Configuration Model

**Decision**: Three GUC variables with PGC_SIGHUP context.

**Variables**:
| GUC | Type | Default | Purpose |
|-----|------|---------|---------|
| `pglogical.conflict_history_enabled` | bool | false | Master enable/disable |
| `pglogical.conflict_history_store_tuples` | bool | true | Include tuple JSONB |
| `pglogical.conflict_history_max_tuple_size` | int | 1024 | Truncation threshold |

**Rationale**:
- Default OFF for backward compatibility (Constitution Principle II)
- PGC_SIGHUP allows runtime changes via `pg_reload_conf()`
- Follows existing pglogical GUC patterns

**Pattern from existing code** (pglogical.c):
```c
DefineCustomBoolVariable("pglogical.conflict_history_enabled",
    "Record conflicts to pglogical.conflict_history table",
    NULL,
    &pglogical_conflict_history_enabled,
    false,
    PGC_SIGHUP, 0,
    NULL, NULL, NULL);
```

### 5. Integration Point

**Decision**: Call `pglogical_record_conflict()` from within `pglogical_report_conflict()`.

**Rationale**:
- All conflict data already available at this point
- Called after resolution, before tuple application
- Within transaction context (SPI available)
- Minimal code changes to existing flow

**Data Available at Integration Point**:
- Conflict type and resolution
- Local tuple (may be NULL)
- Remote tuple
- Subscription context (MySubscription global)
- Origin information (replorigin_session_*)
- Conflict index OID

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    pglogical Apply Worker                       │
├─────────────────────────────────────────────────────────────────┤
│  pglogical_apply_heap.c                                         │
│  ├── handle_insert() ──► conflict detected                     │
│  ├── handle_update() ──► conflict detected                     │
│  └── handle_delete() ──► conflict detected                     │
│           │                                                     │
│           ▼                                                     │
│  try_resolve_conflict()                                         │
│           │                                                     │
│           ▼                                                     │
│  pglogical_report_conflict()                                    │
│  ├── [existing] ereport() to server log                        │
│  └── [NEW] pglogical_record_conflict() ──► INSERT via SPI      │
│                                      │                          │
│                                      ▼                          │
│                          pglogical.conflict_history             │
│                          (partitioned table)                    │
└─────────────────────────────────────────────────────────────────┘
```

## Files to Modify/Create

| File | Action | Purpose |
|------|--------|---------|
| `pglogical_conflict_history.c` | Create | Recording logic, tuple-to-JSONB |
| `pglogical_conflict_history.h` | Create | Header with function declarations |
| `pglogical_conflict.c` | Modify | Add call to `pglogical_record_conflict()` |
| `pglogical.c` | Modify | Add GUC variable definitions |
| `pglogical--2.4.6--2.5.0.sql` | Create | Schema migration |
| `Makefile` | Modify | Add new object file |
| `sql/conflict_history.sql` | Create | Regression tests |
| `expected/conflict_history.out` | Create | Expected test output |

## Dependencies Resolved

1. **JSONB APIs**: Available PG 9.4+, compat headers handle DatumGetJsonb
2. **SPI**: Already used in pglogical_apply_spi.c, patterns established
3. **Partitioning**: Declarative partitioning requires PG 10+ (acceptable)
4. **GUC**: Standard PostgreSQL API, existing patterns in pglogical.c
5. **Subscription Context**: `MySubscription` global available in apply worker

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Recording overhead | Feature disabled by default; optional tuple storage |
| Partition growth | Monthly partitions + cleanup function |
| Recording failure | PG_TRY/PG_CATCH prevents apply abort |
| Version compatibility | JSONB available 9.4+; partitioning 10+ |
| Schema migration | Standard extension upgrade path |

## References

- Design proposal: `/features/conflict_history.md`
- Existing conflict handling: `pglogical_conflict.c`
- SPI patterns: `pglogical_apply_spi.c`
- GUC patterns: `pglogical.c` lines 778-853
- Compat headers: `compat*/pglogical_compat.h`
