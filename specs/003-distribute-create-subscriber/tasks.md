# Tasks: Distribute pglogical_create_subscriber

**Input**: Design documents from `/specs/003-distribute-create-subscriber/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, quickstart.md

**Tests**: Tests are NOT explicitly requested for this feature. Verification is via `--help` command and existing TAP test.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

This is a PostgreSQL extension with packaging automation. Modified files are:
- `.github/workflows/release.yml` - CI/CD release workflow
- `packaging/windows/pglogical.wxs` - Windows MSI installer definition
- `packaging/unix/install.sh` - Unix installation script
- `packaging/unix/README.md` - Unix package documentation
- `packaging/windows/README.md` - Windows package documentation

---

## Phase 1: Setup (Not Required)

**Purpose**: This feature modifies existing infrastructure only; no new project setup is needed.

No setup tasks required - all files already exist in the repository.

---

## Phase 2: Foundational (Not Required)

**Purpose**: This feature has no foundational/blocking prerequisites.

The `pglogical_create_subscriber` executable is already built by the existing Makefile and CMakeLists.txt. No changes to build infrastructure are required.

**Checkpoint**: Ready to proceed with user story implementation.

---

## Phase 3: User Story 1 - Windows MSI Installation (Priority: P1) - MVP

**Goal**: Windows MSI packages install `pglogical_create_subscriber.exe` to PostgreSQL bin directory.

**Independent Test**: Install MSI package and run `pglogical_create_subscriber --help` from command line.

### Implementation for User Story 1

- [X] T001 [US1] Add BINDIR StandardDirectory reference to WiX installer in `packaging/windows/pglogical.wxs`
- [X] T002 [US1] Add Executables Component with pglogical_create_subscriber.exe in `packaging/windows/pglogical.wxs`
- [X] T003 [US1] Add ComponentRef for Executables to Feature element in `packaging/windows/pglogical.wxs`

**Checkpoint**: MSI installer now includes the executable. Can be tested by building MSI and verifying installation.

---

## Phase 4: User Story 2 - Linux tar.gz Installation (Priority: P1)

**Goal**: Linux tar.gz packages include executable in bin/ directory and install.sh installs it.

**Independent Test**: Extract tar.gz, run install.sh, verify `pglogical_create_subscriber --help` works.

### Implementation for User Story 2

- [X] T004 [P] [US2] Add bin/ directory creation and executable copy for Linux in `.github/workflows/release.yml`
- [X] T005 [US2] Add BINDIR detection via pg_config --bindir in `packaging/unix/install.sh`
- [X] T006 [US2] Add loop to install executables from bin/ subdirectory in `packaging/unix/install.sh` (handle edge cases: missing bin dir, permissions via sudo)

**Checkpoint**: Linux packages include executable and install.sh installs it to PostgreSQL bin directory.

---

## Phase 5: User Story 3 - macOS tar.gz Installation (Priority: P1)

**Goal**: macOS tar.gz packages include executable in bin/ directory and install.sh installs it.

**Independent Test**: Extract tar.gz on macOS, run install.sh, verify `pglogical_create_subscriber --help` works.

### Implementation for User Story 3

- [X] T007 [US3] Add bin/ directory creation and executable copy for macOS in `.github/workflows/release.yml`

**Checkpoint**: macOS packages include executable. The install.sh changes from US2 handle macOS as well.

---

## Phase 6: User Story 4 - Windows ZIP Manual Installation (Priority: P2)

**Goal**: Windows ZIP packages include executable in bin/ subdirectory.

**Independent Test**: Extract ZIP and verify bin/pglogical_create_subscriber.exe exists.

### Implementation for User Story 4

- [X] T008 [US4] Add bin/ directory creation and executable copy for Windows ZIP in `.github/workflows/release.yml`

**Checkpoint**: Windows ZIP packages include executable in bin/ directory.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation updates that affect multiple user stories

- [X] T009 [P] Add bundled executable documentation section in `packaging/unix/README.md`
- [X] T010 [P] Add bundled executable documentation section in `packaging/windows/README.md`
- [X] T011 Run quickstart.md validation: verify bin/ directory exists in each package type (MSI, ZIP, Linux tar.gz, macOS tar.gz), confirm executable permissions are correct, test `--help` output after installation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Not required
- **Foundational (Phase 2)**: Not required
- **User Stories (Phase 3-6)**: Can proceed immediately
  - US1 (MSI): Independent - only modifies pglogical.wxs
  - US2 (Linux): Independent - modifies release.yml (Linux section) and install.sh
  - US3 (macOS): Depends on US2 for install.sh changes; modifies release.yml (macOS section)
  - US4 (Windows ZIP): Independent - modifies release.yml (Windows ZIP section)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (MSI)**: No dependencies - can start immediately
- **User Story 2 (Linux)**: No dependencies - can start immediately
- **User Story 3 (macOS)**: Shares install.sh with US2; start after US2 or coordinate changes
- **User Story 4 (Windows ZIP)**: No dependencies - can start immediately

### Within Each User Story

- T001-T003 (US1): Must be sequential - building WiX component structure
- T004-T006 (US2): T004 can be parallel with T005-T006; T005 before T006
- T007 (US3): Independent of other stories
- T008 (US4): Independent of other stories
- T009-T010 (Polish): Can run in parallel; T011 runs last

### Parallel Opportunities

```bash
# Maximum parallelism: After Phase 2, these can all start simultaneously:
# - T001 (US1 - pglogical.wxs)
# - T004 (US2 - release.yml Linux section)
# - T005 (US2 - install.sh BINDIR detection)
# - T008 (US4 - release.yml Windows ZIP section)

# Then:
# - T002-T003 (US1 continuation)
# - T006 (US2 continuation - after T005)
# - T007 (US3 - after US2 install.sh changes or in parallel if coordinated)

# Finally, all documentation in parallel:
# - T009 (packaging/unix/README.md)
# - T010 (packaging/windows/README.md)
```

---

## Parallel Example: Cross-Story Parallelism

```bash
# Launch independent file modifications in parallel:
Task: "Add BINDIR StandardDirectory reference to WiX installer in packaging/windows/pglogical.wxs"
Task: "Add bin/ directory creation and executable copy for Linux in .github/workflows/release.yml"
Task: "Add bin/ directory creation and executable copy for Windows ZIP in .github/workflows/release.yml"
Task: "Add BINDIR detection via pg_config --bindir in packaging/unix/install.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001-T003: Windows MSI changes
2. **STOP and VALIDATE**: Build MSI locally, verify pglogical_create_subscriber.exe installs
3. This covers the primary Windows distribution method

### Incremental Delivery

1. US1 (MSI) complete → Windows users with MSI can use utility
2. US2 (Linux) complete → Linux users can use utility
3. US3 (macOS) complete → macOS users can use utility
4. US4 (Windows ZIP) complete → All package types covered
5. Polish complete → Documentation updated for all platforms

### Parallel Team Strategy

With multiple developers working on different files:

1. Developer A: T001-T003 (pglogical.wxs only)
2. Developer B: T004, T007, T008 (release.yml sections)
3. Developer C: T005-T006 (install.sh)
4. Documentation: Anyone after implementation complete

---

## Notes

- All tasks modify existing files; no new files created
- [P] tasks can run in parallel with other [P] tasks in same phase
- Each user story delivers value to a specific platform's users
- Verification is via `pglogical_create_subscriber --help` after package installation
- Existing TAP test `t/010_pglogical_create_subscriber.pl` validates utility functionality
- Total: 11 tasks across 4 user stories + documentation
