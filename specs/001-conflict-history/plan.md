# Implementation Plan: Conflict History Persistence

**Branch**: `001-conflict-history` | **Date**: 2025-12-25 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-conflict-history/spec.md`

## Summary

Add native conflict history persistence to pglogical. The feature extends the existing `pglogical_report_conflict()` function to additionally record conflict data to a queryable table (`pglogical.conflict_history`) within the apply worker transaction. This provides DBAs with programmatic access to conflict information without parsing server logs. The feature is disabled by default for backward compatibility and controlled via GUC variables.

## Technical Context

**Language/Version**: C (PostgreSQL extension, C99 compatible)
**Primary Dependencies**: PostgreSQL Server API (9.4-18+), SPI, JSONB functions
**Storage**: PostgreSQL catalog tables (within `pglogical` schema), monthly partitioned
**Testing**: PostgreSQL regression test framework (`make installcheck`)
**Target Platform**: Linux, macOS, Windows (PostgreSQL supported platforms)
**Project Type**: Single PostgreSQL extension project
**Performance Goals**: <5% overhead to apply worker transaction time under normal conflict rates (<100 conflicts/sec)
**Constraints**: Must not abort apply transactions on recording failure; graceful degradation required
**Scale/Scope**: Tables may grow to 100k+ records; must support efficient queries and cleanup

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Compliance Notes |
|-----------|--------|-----------------|
| I. PostgreSQL Version Compatibility | PASS | Feature uses SPI and JSONB which are available in PG 9.4+. Version guards will be used for any API differences. |
| II. Backward Compatibility | PASS | Feature defaults to OFF (`conflict_history_enabled = false`). Existing ereport() logging unchanged. Extension upgrade adds table but doesn't require migration of existing data. |
| III. Testing Discipline | PASS | Will include regression tests for conflict recording, partition management, and edge cases (recording failures). |
| IV. Code Quality & Memory Safety | PASS | Will follow existing SPI patterns from `pglogical_apply_spi.c`. Memory allocations in appropriate contexts. Error handling via ereport/elog. |
| V. Replication Integrity | PASS | Recording is additive observation only; does not modify conflict resolution logic or replication data path. Recording failures logged but do not abort apply. |

**Gate Status**: PASS - All constitution principles satisfied.

## Project Structure

### Documentation (this feature)

```text
specs/001-conflict-history/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (SQL function signatures)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
# Existing pglogical structure - files to modify/add:
pglogical_conflict.c         # Modify: Add recording logic to pglogical_report_conflict()
pglogical_conflict.h         # Modify: Add new function declarations if needed
pglogical.c                  # Modify: Add GUC variable definitions in _PG_init()
pglogical_conflict_history.c # NEW: Conflict history recording and tuple-to-JSONB conversion
pglogical_conflict_history.h # NEW: Header for conflict history functions

# SQL schema files:
pglogical--2.4.6--2.5.0.sql  # NEW: Schema migration adding conflict_history table, views, functions
pglogical.control            # Modify: Update default_version to 2.5.0

# Test files:
sql/conflict_history.sql     # NEW: Regression tests for conflict history feature
expected/conflict_history.out # NEW: Expected output for regression tests
```

**Structure Decision**: This is an existing PostgreSQL C extension. New C source files will be added to the repository root alongside existing `pglogical_*.c` files. SQL schema changes will use the standard PostgreSQL extension upgrade path with a migration file.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations detected. Implementation follows existing patterns in the codebase.

## Constitution Check (Post-Design Re-evaluation)

*Re-evaluated after Phase 1 design completion.*

| Principle | Status | Post-Design Notes |
|-----------|--------|-------------------|
| I. PostgreSQL Version Compatibility | PASS | Design uses declarative partitioning (PG 10+). SPI and JSONB APIs verified compatible across versions. DatumGetJsonb compatibility handled via existing compat headers. |
| II. Backward Compatibility | PASS | Default OFF confirmed in GUC design. Extension upgrade path defined in `pglogical--2.4.6--2.5.0.sql`. No changes to existing function signatures. |
| III. Testing Discipline | PASS | Regression test plan defined: conflict_history.sql covering recording, partition management, and failure scenarios. |
| IV. Code Quality & Memory Safety | PASS | SPI pattern from `pglogical_apply_spi.c` applied. PG_TRY/PG_CATCH for graceful error handling. Memory contexts documented. |
| V. Replication Integrity | PASS | Recording is strictly observational. Error handling ensures apply transaction never aborted by recording failures. |

**Post-Design Gate Status**: PASS - Design validates all constitution principles.

## Design Artifacts Generated

| Artifact | Path | Purpose |
|----------|------|---------|
| research.md | specs/001-conflict-history/research.md | Technical decisions and rationale |
| data-model.md | specs/001-conflict-history/data-model.md | Table schema, indexes, partitioning |
| sql-functions.md | specs/001-conflict-history/contracts/sql-functions.md | SQL function contracts |
| c-api.md | specs/001-conflict-history/contracts/c-api.md | C function contracts |
| quickstart.md | specs/001-conflict-history/quickstart.md | User guide for feature |

## Next Steps

Run `/speckit.tasks` to generate the implementation task list based on these design artifacts.
