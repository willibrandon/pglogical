# Implementation Plan: Distribute pglogical_create_subscriber

**Branch**: `003-distribute-create-subscriber` | **Date**: 2026-01-08 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/003-distribute-create-subscriber/spec.md`

## Summary

Include the `pglogical_create_subscriber` executable in all release packages (Windows MSI, Windows ZIP, Linux tar.gz, macOS tar.gz). The utility is already built during the normal build process but is not packaged. This requires modifying the packaging scripts, WiX installer definition, CI/CD workflows, and installation script to include the executable in the appropriate `bin/` directory.

## Technical Context

**Language/Version**: C (PostgreSQL extension), Bash (scripts), WiX v5 (Windows MSI), YAML (GitHub Actions)
**Primary Dependencies**: WiX Toolset v5, GitHub Actions runners, pg_config
**Storage**: N/A (packaging feature, no data storage)
**Testing**: Manual verification via `--help` command, existing TAP test (`t/010_pglogical_create_subscriber.pl`)
**Target Platform**: Windows (x64), Linux (x64), macOS (ARM64)
**Project Type**: PostgreSQL C extension with packaging automation
**Performance Goals**: N/A (packaging feature)
**Constraints**: Must work with existing PostgreSQL installation paths
**Scale/Scope**: 4 package types, 4 PostgreSQL versions (15-18), 12 CI matrix jobs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Applicable | Status | Notes |
|-----------|-----------|--------|-------|
| I. PostgreSQL Version Compatibility | Yes | PASS | No code changes to utility; packaging only |
| II. Backward Compatibility | Yes | PASS | Additive change; no existing behavior modified |
| III. Testing Discipline | Yes | PASS | Existing TAP test covers utility; acceptance via --help |
| IV. Code Quality & Memory Safety | No | N/A | No C code changes |
| V. Replication Integrity | No | N/A | No data path changes |
| VI. Implementation Completeness | Yes | PASS | All 4 package types addressed, no stubs |

**Gate Result**: PASS - Proceed to Phase 0

## Project Structure

### Documentation (this feature)

```text
specs/003-distribute-create-subscriber/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (files to modify)

```text
packaging/
├── unix/
│   ├── install.sh       # Add bin/ directory handling
│   └── README.md        # Document bundled executable
└── windows/
    ├── pglogical.wxs    # Add BINDIR component for exe
    └── README.md        # Document bundled executable

.github/workflows/
└── release.yml          # Add bin/ directory and copy executable for all platforms
```

**Structure Decision**: This is a packaging-only feature. No new source files are created; existing packaging infrastructure files are modified to include the already-built executable.

## Complexity Tracking

No constitution violations to justify. This is a minimal-complexity packaging change.

## Phase 0: Research Complete

All technical unknowns resolved. See [research.md](research.md) for details on:
- Build process (no changes needed)
- WiX v5 packaging patterns
- GitHub Actions modifications
- Install script enhancement
- Documentation updates

## Phase 1: Design Complete

### Artifacts Generated

| Artifact | Purpose | Status |
|----------|---------|--------|
| research.md | Technical decisions and rationale | Complete |
| quickstart.md | Implementation verification guide | Complete |

### Data Model

Not applicable - this is a packaging feature with no data entities.

### API Contracts

Not applicable - no API endpoints or interfaces defined.

### Constitution Re-check (Post-Design)

| Principle | Status | Notes |
|-----------|--------|-------|
| I. PostgreSQL Version Compatibility | PASS | Packaging changes are version-agnostic |
| II. Backward Compatibility | PASS | No breaking changes to existing packages |
| III. Testing Discipline | PASS | Verification via --help + existing TAP test |
| VI. Implementation Completeness | PASS | All 5 files fully specified |

**Gate Result**: PASS - Ready for Phase 2 (/speckit.tasks)

## Implementation Scope

### Files to Modify

1. **`.github/workflows/release.yml`**
   - Linux packaging section: Add bin/ directory, copy executable
   - macOS packaging section: Add bin/ directory, copy executable
   - Windows ZIP packaging section: Add bin/ directory, copy executable

2. **`packaging/windows/pglogical.wxs`**
   - Add BINDIR StandardDirectory reference
   - Add Executables Component with pglogical_create_subscriber.exe
   - Add ComponentRef to Feature element

3. **`packaging/unix/install.sh`**
   - Add BINDIR detection via `pg_config --bindir`
   - Add loop to install executables from bin/ subdirectory
   - Handle permissions (sudo) for bin directory

4. **`packaging/unix/README.md`**
   - Add section describing bundled executable
   - Add verification command example

5. **`packaging/windows/README.md`**
   - Add section describing bundled executable
   - Add verification command example

### Files Created (None)

No new files are created for this feature.
