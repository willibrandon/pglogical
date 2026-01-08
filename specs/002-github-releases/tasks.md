# Tasks: GitHub Releases Distribution

**Input**: Design documents from `/specs/002-github-releases/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not explicitly requested in specification. Tests are manual verification per acceptance scenarios.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US3, US7)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md structure:
- `.github/workflows/` - GitHub Actions workflow definitions
- `packaging/windows/` - Windows-specific packaging (WiX, README)
- `packaging/unix/` - Linux/macOS packaging (install script)

---

## Phase 1: Setup (Directory Structure)

**Purpose**: Create project directory structure for CI/CD infrastructure

- [x] T001 Create `.github/workflows/` directory structure
- [x] T002 [P] Create `packaging/windows/` directory structure
- [x] T003 [P] Create `packaging/unix/` directory structure

---

## Phase 2: Foundational (CI Workflow)

**Purpose**: Core CI infrastructure that MUST be complete before release workflow can function

**⚠️ CRITICAL**: Release workflow depends on CI workflow patterns; CI must be working first

- [x] T004 Create CI workflow file skeleton in `.github/workflows/ci.yml`
- [x] T005 Add checkout step with `submodules: recursive` in `.github/workflows/ci.yml`
- [x] T006 Define build matrix (PG 13-18, ubuntu-latest, windows-2022, macos-13, macos-14) in `.github/workflows/ci.yml`
- [x] T007 Add Linux PostgreSQL installation steps (apt install postgresql-server-dev-XX) in `.github/workflows/ci.yml`
- [x] T008 [P] Add macOS PostgreSQL installation steps (brew install postgresql@XX) in `.github/workflows/ci.yml`
- [x] T009 [P] Add Windows PostgreSQL installation steps (choco install postgresqlXX) in `.github/workflows/ci.yml`
- [x] T010 Add Linux/macOS build steps (make clean all) in `.github/workflows/ci.yml`
- [x] T011 [P] Add Windows build steps (cmake with MSVC) in `.github/workflows/ci.yml`
- [x] T012 Add Linux/macOS regression test step (make check) in `.github/workflows/ci.yml`
- [x] T013 Configure fail-fast: false in build matrix in `.github/workflows/ci.yml`
- [x] T014 Add workflow triggers (push to REL2_x_STABLE, windows-build; PR to REL2_x_STABLE) in `.github/workflows/ci.yml`

**Checkpoint**: CI workflow complete - PRs can be validated across all platforms

---

## Phase 3: User Story 7 - CI Validation on Pull Requests (Priority: P2) 🎯 MVP

**Goal**: Contributors can validate their changes build correctly on all supported platforms via CI

**Independent Test**: Open a pull request with a minor change and verify build jobs run for all platform/PostgreSQL version combinations

### Implementation for User Story 7

> Note: Most tasks completed in Phase 2. This phase adds PR-specific enhancements.

- [x] T015 [US7] Add artifact upload for test results on failure in `.github/workflows/ci.yml`
- [x] T016 [US7] Add workflow run summary with build status matrix in `.github/workflows/ci.yml`
- [x] T017 [US7] Document CI workflow and branch protection requirements in `packaging/README-CI.md`

**Checkpoint**: US7 complete - CI validates PRs and shows clear per-job status

---

## Phase 4: User Story 3 - Automatic Release on Git Tag (Priority: P1)

**Goal**: Release pipeline automatically triggers when pushing a version tag (v*)

**Independent Test**: Push a tag matching `v*` pattern and verify GitHub Actions workflows start building for all platform/PostgreSQL version combinations

### Implementation for User Story 3

- [x] T018 [US3] Create release workflow file skeleton in `.github/workflows/release.yml`
- [x] T019 [US3] Add tag trigger (on push tags: v*) in `.github/workflows/release.yml`
- [x] T020 [US3] Add version extraction step (strip 'v' prefix from tag) in `.github/workflows/release.yml`
- [x] T021 [US3] Copy build matrix and platform steps from ci.yml to `.github/workflows/release.yml`
- [x] T022 [P] [US3] Add artifact packaging step for Linux (tar.gz with naming convention) in `.github/workflows/release.yml`
- [x] T023 [P] [US3] Add artifact packaging step for Windows (zip with naming convention) in `.github/workflows/release.yml`
- [x] T024 [P] [US3] Add artifact packaging step for macOS (tar.gz with naming convention) in `.github/workflows/release.yml`
- [x] T025 [US3] Add workflow artifact upload for each platform in `.github/workflows/release.yml`
- [x] T026 [US3] Add prerelease detection (tag contains hyphen) in `.github/workflows/release.yml`
- [x] T027 [US3] Create release job with needs: [build] in `.github/workflows/release.yml`
- [x] T028 [US3] Add artifact download step in release job in `.github/workflows/release.yml`
- [x] T029 [US3] Add GitHub Release creation with softprops/action-gh-release in `.github/workflows/release.yml`

**Checkpoint**: US3 complete - Pushing v* tag creates GitHub Release with all binary artifacts

---

## Phase 5: User Story 1 - Download Pre-built Binary for My Platform (Priority: P1)

**Goal**: Users can download pre-built binary packages for their specific platform and PostgreSQL version

**Independent Test**: Navigate to a GitHub Release page, download a package for a specific platform/PostgreSQL version, and verify the package contains expected files

### Implementation for User Story 1

> Note: Release workflow from US3 creates artifacts. This phase ensures correct contents.

- [x] T030 [US1] Ensure Linux packages include pglogical.so, pglogical_output.so, pglogical.control, and SQL files in `.github/workflows/release.yml`
- [x] T031 [P] [US1] Ensure Windows packages include pglogical.dll, pglogical_output.dll, pglogical.control, SQL files, and README.md in `.github/workflows/release.yml`
- [x] T032 [P] [US1] Ensure macOS packages include pglogical.dylib, pglogical_output.dylib, pglogical.control, and SQL files in `.github/workflows/release.yml`
- [x] T033 [US1] Verify artifact naming follows pattern `pglogical-{version}-pg{pg_version}-{platform}-{arch}.{ext}` in `.github/workflows/release.yml`
- [x] T034 [US1] Add release notes template with platform-specific installation instructions in `.github/workflows/release.yml`

**Checkpoint**: US1 complete - Users can download correctly named packages containing all required files

---

## Phase 6: User Story 6 - Install on Linux/macOS with Helper Script (Priority: P2)

**Goal**: Linux/macOS users can run install.sh to install the extension without memorizing PostgreSQL paths

**Independent Test**: Extract package, run `./install.sh`, verify files are copied to correct PostgreSQL directories

### Implementation for User Story 6

- [x] T035 [US6] Create install.sh skeleton with shebang and set -e in `packaging/unix/install.sh`
- [x] T036 [US6] Add pg_config detection (check PATH, then PG_CONFIG env var) in `packaging/unix/install.sh`
- [x] T037 [US6] Add error message if pg_config not found in `packaging/unix/install.sh`
- [x] T038 [US6] Implement library file copy to $(pg_config --pkglibdir) in `packaging/unix/install.sh`
- [x] T039 [US6] Implement extension file copy to $(pg_config --sharedir)/extension in `packaging/unix/install.sh`
- [x] T040 [US6] Add sudo detection for privileged directories in `packaging/unix/install.sh`
- [x] T041 [US6] Add success message with installed file locations in `packaging/unix/install.sh`
- [x] T042 [US6] Make script executable (chmod +x) and include in package in `.github/workflows/release.yml`

**Checkpoint**: US6 complete - Users can install with `./install.sh` using pg_config auto-detection

---

## Phase 7: User Story 2 - Install via Windows MSI Installer (Priority: P2)

**Goal**: Windows administrators can use MSI installer with automatic PostgreSQL path detection

**Independent Test**: Run MSI installer on Windows with PostgreSQL installed, verify it detects correct directory and registers for uninstall

### Implementation for User Story 2

- [x] T043 [US2] Create WiX v5 project structure with Product element in `packaging/windows/pglogical.wxs`
- [x] T044 [US2] Add RegistrySearch for PostgreSQL installation path detection in `packaging/windows/pglogical.wxs`
- [x] T045 [US2] Add fallback directory search for common PostgreSQL paths in `packaging/windows/pglogical.wxs`
- [x] T046 [US2] Add WixUI_InstallDir for directory browse fallback in `packaging/windows/pglogical.wxs`
- [x] T047 [US2] Define ComponentGroup for library files (pglogical.dll, pglogical_output.dll) in `packaging/windows/pglogical.wxs`
- [x] T048 [US2] Define ComponentGroup for extension files (control, SQL) in `packaging/windows/pglogical.wxs`
- [x] T049 [US2] Add MajorUpgrade element for clean upgrades in `packaging/windows/pglogical.wxs`
- [x] T050 [US2] Configure unique UpgradeCode per PostgreSQL version (com.2ndquadrant.pglogical.postgresqlXX) in `packaging/windows/pglogical.wxs`
- [x] T051 [US2] Create Windows installation README with manual instructions in `packaging/windows/README.md`
- [x] T052 [US2] Add WiX v5 installation step (dotnet tool install wix) in `.github/workflows/release.yml`
- [x] T053 [US2] Add MSI build step with version and PG version parameters in `.github/workflows/release.yml`
- [x] T054 [US2] Add MSI artifact to release assets in `.github/workflows/release.yml`

**Checkpoint**: US2 complete - Windows users can install via MSI with automatic path detection

---

## Phase 8: User Story 4 - Download Source Package with Dependencies (Priority: P3)

**Goal**: Developers can download complete source package including submodule contents

**Independent Test**: Download source tarball, extract it, run `make` without needing git submodule commands

### Implementation for User Story 4

- [x] T055 [US4] Create source archive job in `.github/workflows/release.yml`
- [x] T056 [US4] Checkout with submodules: recursive and fetch-depth: 0 for source job in `.github/workflows/release.yml`
- [x] T057 [US4] Create source tar.gz with submodule contents included in `.github/workflows/release.yml`
- [x] T058 [P] [US4] Create source zip with submodule contents included in `.github/workflows/release.yml`
- [x] T059 [US4] Name source archives as `pglogical-{version}-source.{ext}` in `.github/workflows/release.yml`
- [x] T060 [US4] Add source archives to release assets in `.github/workflows/release.yml`

**Checkpoint**: US4 complete - Source packages build without git submodule initialization

---

## Phase 9: User Story 5 - Verify Download Integrity (Priority: P3)

**Goal**: Security-conscious users can verify downloads via SHA256 checksums

**Independent Test**: Download checksums.txt, download any artifact, compute SHA256 hash locally, compare against published checksum

### Implementation for User Story 5

- [x] T061 [US5] Generate SHA256 checksums for all artifacts in release job in `.github/workflows/release.yml`
- [x] T062 [US5] Create checksums.txt file with all artifact hashes in `.github/workflows/release.yml`
- [x] T063 [US5] Add checksums.txt to release assets in `.github/workflows/release.yml`

**Checkpoint**: US5 complete - All release artifacts have verifiable SHA256 checksums

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Final improvements and documentation

- [x] T064 [P] Add comments documenting workflow structure in `.github/workflows/ci.yml`
- [x] T065 [P] Add comments documenting workflow structure in `.github/workflows/release.yml`
- [x] T066 Verify all artifact naming follows FR-015 pattern in `.github/workflows/release.yml`
- [x] T067 [P] Add error handling for missing PostgreSQL versions in `.github/workflows/ci.yml`
- [x] T068 Test complete release workflow with a test tag (v2.5.0-rc16)
- [x] T069 Validate install.sh works on Ubuntu and macOS
- [x] T070 Validate MSI installer on Windows with PostgreSQL 17
- [x] T071 Run quickstart.md verification checklist

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup - establishes CI workflow
- **US7 (Phase 3)**: Depends on Phase 2 - enhances CI for PR validation
- **US3 (Phase 4)**: Depends on Phase 2 - creates release workflow using CI patterns
- **US1 (Phase 5)**: Depends on US3 - ensures artifact contents are correct
- **US6 (Phase 6)**: Can start after Phase 1 - independent install script development
- **US2 (Phase 7)**: Can start after Phase 1 - independent MSI development
- **US4 (Phase 8)**: Depends on US3 - adds source package to release workflow
- **US5 (Phase 9)**: Depends on US3 - adds checksums to release workflow
- **Polish (Phase 10)**: Depends on all user stories complete

### User Story Dependencies

```
Phase 1 (Setup) ─────────┬──────────────────────────────────────────────────┐
                         │                                                  │
                         ▼                                                  │
Phase 2 (Foundation) ────┼──────────────────────────────────────────────────┤
                         │                                                  │
         ┌───────────────┼───────────────┐                                  │
         │               │               │                                  │
         ▼               ▼               ▼                                  │
    US7 (Phase 3)   US3 (Phase 4)   US6 (Phase 6)  ←── Can start parallel   │
                         │               │                                  │
                         │               │          US2 (Phase 7)  ←────────┘
                         │               │               │
         ┌───────────────┴───────────┐   │               │
         │               │           │   │               │
         ▼               ▼           ▼   ▼               ▼
    US1 (Phase 5)   US4 (Phase 8)   US5 (Phase 9)       │
         │               │           │                   │
         └───────────────┴───────────┴───────────────────┘
                                     │
                                     ▼
                            Phase 10 (Polish)
```

### Within Each Phase

- Tasks marked [P] can run in parallel
- Non-parallel tasks should execute in listed order
- Each phase should be committed as a logical unit

### Parallel Opportunities

**Phase 1 (all parallel)**:
- T001, T002, T003 - different directories

**Phase 2 (platform-specific parallel)**:
- T008, T009 - different platform installation steps
- T010, T011 - different platform build steps

**Phase 4 (packaging parallel)**:
- T022, T023, T024 - different platform packaging steps

**Phase 5 (platform contents parallel)**:
- T031, T032 - different platform artifact contents

**Phase 6, 7 (can work in parallel with each other)**:
- US6 (install script) and US2 (MSI) are independent
- Can be developed by different team members simultaneously

**Phase 8 (archive format parallel)**:
- T057, T058 - tar.gz and zip creation

---

## Parallel Example: Phase 4 (Release Workflow)

```bash
# Launch platform packaging steps together:
Task: "T022 [P] [US3] Add artifact packaging step for Linux in .github/workflows/release.yml"
Task: "T023 [P] [US3] Add artifact packaging step for Windows in .github/workflows/release.yml"
Task: "T024 [P] [US3] Add artifact packaging step for macOS in .github/workflows/release.yml"
```

---

## Implementation Strategy

### MVP First (CI + Release + Binaries)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CI workflow)
3. Complete Phase 3: US7 (CI validation)
4. Complete Phase 4: US3 (release automation)
5. Complete Phase 5: US1 (binary packages)
6. **STOP and VALIDATE**: Push test tag, verify release is created with binaries
7. Deploy/demo if ready

### Incremental Delivery

1. Setup + Foundational + US7 → CI works for PRs
2. Add US3 + US1 → Tag-triggered releases with binaries (Core MVP!)
3. Add US6 → Linux/macOS install script
4. Add US2 → Windows MSI installer
5. Add US4 → Source packages
6. Add US5 → Checksums
7. Each addition enhances distribution without breaking existing functionality

### Parallel Team Strategy

With two developers:

1. Team completes Setup + Foundational together
2. Developer A: US7 → US3 → US1 → US4 → US5 (workflow path)
3. Developer B: US6 → US2 (packaging path, can start immediately)
4. Polish phase after both paths complete

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Test workflows by pushing to a test branch before merging
- Verify MSI locally before including in release workflow
