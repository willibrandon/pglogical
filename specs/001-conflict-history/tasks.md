# Tasks: Conflict History Persistence

**Feature**: 001-conflict-history
**Input**: Design documents from `/specs/001-conflict-history/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Regression tests will be included as this is a PostgreSQL extension (standard practice per constitution).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Path Conventions

This is a PostgreSQL C extension project. Files are at repository root:
- C source: `pglogical_*.c`, `pglogical_*.h`
- SQL: `pglogical--*.sql`
- Tests: `sql/*.sql`, `expected/*.out`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization, header files, and build system changes

- [ ] T001 Create header file pglogical_conflict_history.h with GUC extern declarations and function prototypes
- [ ] T002 Add pglogical_conflict_history.o to OBJS in Makefile
- [ ] T003 [P] Create skeleton pglogical_conflict_history.c with includes and empty function stubs

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 Add GUC variable definitions to pglogical.c in _PG_init() for conflict_history_enabled, conflict_history_store_tuples, conflict_history_max_tuple_size
- [ ] T005 Create extension upgrade script pglogical--2.4.6--2.5.0.sql with conflict_history table DDL using PARTITION BY RANGE (recorded_at)
- [ ] T006 [P] Add conflict_history indexes to pglogical--2.4.6--2.5.0.sql (sub_id, relation, conflict_type, resolution)
- [ ] T007 [P] Add initial partition creation for current month in pglogical--2.4.6--2.5.0.sql
- [ ] T008 Update pglogical.control to set default_version to 2.5.0
- [ ] T009 Implement tuple_to_jsonb() internal function in pglogical_conflict_history.c
- [ ] T010 Implement conflict_type_to_string() helper in pglogical_conflict_history.c
- [ ] T011 [P] Implement resolution_to_string() helper in pglogical_conflict_history.c

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Query Conflict History (Priority: P1) 🎯 MVP

**Goal**: Enable DBAs to query replication conflicts from a SQL table instead of parsing logs

**Independent Test**: Enable conflict history, create a replication conflict scenario, query conflict_history table to verify conflict was recorded with all expected metadata

### Implementation for User Story 1

- [ ] T012 [US1] Implement pglogical_record_conflict() main function in pglogical_conflict_history.c with SPI INSERT logic (GUC check added in T019)
- [ ] T013 [US1] Add PG_TRY/PG_CATCH error handling wrapper around SPI operations in pglogical_record_conflict()
- [ ] T014 [US1] Add #include "pglogical_conflict_history.h" to pglogical_conflict.c
- [ ] T015 [US1] Add call to pglogical_record_conflict() at end of pglogical_report_conflict() in pglogical_conflict.c
- [ ] T016 [P] [US1] Add recent_conflicts view to pglogical--2.4.6--2.5.0.sql
- [ ] T017 [US1] Create regression test sql/conflict_history.sql for basic conflict recording and querying
- [ ] T018 [US1] Create expected output expected/conflict_history.out for regression test

**Checkpoint**: User Story 1 complete - conflicts are recorded and queryable

---

## Phase 4: User Story 2 - Configure Conflict Recording (Priority: P1)

**Goal**: Enable DBAs to enable/disable conflict history and control tuple data capture

**Independent Test**: Set GUC variables and verify conflict recording behavior changes (enabled/disabled, with/without tuple data, truncation)

### Implementation for User Story 2

- [ ] T019 [US2] Add early-exit check for pglogical_conflict_history_enabled as first statement in pglogical_record_conflict() before any SPI operations
- [ ] T020 [US2] Add conditional tuple storage based on pglogical_conflict_history_store_tuples in pglogical_record_conflict()
- [ ] T021 [US2] Implement field truncation based on pglogical_conflict_history_max_tuple_size in tuple_to_jsonb()
- [ ] T022 [US2] Add regression tests for GUC configuration in sql/conflict_history.sql (verify default OFF, test enable/disable)
- [ ] T023 [US2] Add regression tests for tuple storage toggle in sql/conflict_history.sql

**Checkpoint**: User Story 2 complete - conflict recording is fully configurable

---

## Phase 5: User Story 3 - View Conflict Statistics (Priority: P2)

**Goal**: Provide aggregate statistics for quick replication health assessment

**Independent Test**: Generate conflicts, call conflict_stats(), verify correct counts

### Implementation for User Story 3

- [ ] T024 [P] [US3] Add conflict_stats() SQL function to pglogical--2.4.6--2.5.0.sql
- [ ] T025 [P] [US3] Add show_subscription_conflicts() SQL function to pglogical--2.4.6--2.5.0.sql
- [ ] T026 [P] [US3] Add conflict_summary view to pglogical--2.4.6--2.5.0.sql
- [ ] T027 [US3] Add regression tests for conflict_stats() and views in sql/conflict_history.sql

**Checkpoint**: User Story 3 complete - statistics and summaries are available

---

## Phase 6: User Story 4 - Manage Conflict History Storage (Priority: P2)

**Goal**: Enable partition management and retention cleanup for production use

**Independent Test**: Call partition management functions, verify partitions created/dropped appropriately

### Implementation for User Story 4

- [ ] T028 [US4] Add conflict_history_ensure_partition() SQL function to pglogical--2.4.6--2.5.0.sql
- [ ] T029 [US4] Add conflict_history_cleanup() SQL function to pglogical--2.4.6--2.5.0.sql
- [ ] T030 [US4] Implement ensure_partition_exists() C helper in pglogical_conflict_history.c (calls SQL function via SPI)
- [ ] T031 [US4] Add call to ensure_partition_exists() before INSERT in pglogical_record_conflict()
- [ ] T032 [US4] Add regression tests for partition management in sql/conflict_history.sql

**Checkpoint**: User Story 4 complete - partition management is functional

---

## Phase 7: User Story 5 - Investigate Specific Conflicts (Priority: P3)

**Goal**: Enable detailed tuple inspection for deep troubleshooting

**Independent Test**: Create conflict with known tuple values, verify local_tuple and remote_tuple JSONB contain expected field values

### Implementation for User Story 5

- [ ] T033 [US5] Add TOAST value handling to tuple_to_jsonb() (store "(unchanged-toast-datum)" for external TOAST)
- [ ] T034 [US5] Add NULL handling for dropped columns in tuple_to_jsonb()
- [ ] T035 [US5] Add regression tests for tuple JSONB content verification in sql/conflict_history.sql

**Checkpoint**: User Story 5 complete - full tuple inspection available

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final validation, documentation, and cleanup

- [ ] T036 [P] Add COMMENT ON statements for all new objects in pglogical--2.4.6--2.5.0.sql
- [ ] T037 [P] Verify conflict_history table inherits pglogical schema permissions (superuser/replication roles only)
- [ ] T038 [P] Verify all regression tests pass with make installcheck
- [ ] T039 Run quickstart.md validation steps manually
- [ ] T040 Update expected/conflict_history.out with final test output

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - US1 and US2 can proceed in parallel after Foundational
  - US3 and US4 can proceed after US1/US2 (need recording to work)
  - US5 can proceed after US1 (enhances tuple handling)
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - Core recording functionality
- **User Story 2 (P1)**: Can start after T012 in US1 - Configures the recording added by US1
- **User Story 3 (P2)**: Can start after US1 complete - Adds statistics over recorded data
- **User Story 4 (P2)**: Can start after US1 complete - Adds partition management
- **User Story 5 (P3)**: Can start after T009 (tuple_to_jsonb) - Enhances tuple handling

### Within Each User Story

- SQL schema before C implementation (where applicable)
- C implementation before integration calls
- Tests at end of each story phase
- Story complete before moving to next priority

### Parallel Opportunities

Within Foundational:
- T006, T007 can run in parallel (both modify pglogical--2.4.6--2.5.0.sql but different sections)
- T010, T011 can run in parallel (separate helper functions)

Within User Stories:
- T016 can run in parallel with T012-T015 (SQL view vs C code)
- T024, T025, T026 can all run in parallel (independent SQL functions/views)

---

## Parallel Example: Foundational Phase

```bash
# After T005 creates the upgrade script, these can run in parallel:
Task: T006 - Add indexes to pglogical--2.4.6--2.5.0.sql
Task: T007 - Add initial partition to pglogical--2.4.6--2.5.0.sql

# These helper functions can be written in parallel:
Task: T010 - Implement conflict_type_to_string() in pglogical_conflict_history.c
Task: T011 - Implement resolution_to_string() in pglogical_conflict_history.c
```

## Parallel Example: User Story 3

```bash
# All these SQL additions can run in parallel:
Task: T024 - Add conflict_stats() SQL function
Task: T025 - Add show_subscription_conflicts() SQL function
Task: T026 - Add conflict_summary view
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T011) - **CRITICAL, blocks all stories**
3. Complete Phase 3: User Story 1 (T012-T018)
4. Complete Phase 4: User Story 2 (T019-T023)
5. **STOP and VALIDATE**: Test conflict recording with GUC configuration
6. Deploy/demo if ready - MVP delivers queryable, configurable conflict history

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test recording → Working conflict capture
3. Add User Story 2 → Test configuration → Fully configurable
4. Add User Story 3 → Test statistics → Monitoring capability
5. Add User Story 4 → Test partitions → Production-ready storage
6. Add User Story 5 → Test tuple details → Advanced troubleshooting

### File Modification Summary

| File | Tasks | Action |
|------|-------|--------|
| pglogical_conflict_history.h | T001 | Create |
| pglogical_conflict_history.c | T003, T009-T013, T019-T021, T030, T033-T034 | Create |
| pglogical_conflict.c | T014-T015 | Modify |
| pglogical.c | T004 | Modify |
| pglogical--2.4.6--2.5.0.sql | T005-T007, T016, T024-T026, T028-T029, T036 | Create |
| pglogical.control | T008 | Modify |
| Makefile | T002 | Modify |
| sql/conflict_history.sql | T017, T022-T023, T027, T032, T035 | Create |
| expected/conflict_history.out | T018, T040 | Create |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- This is a PostgreSQL C extension - use make installcheck for regression tests
