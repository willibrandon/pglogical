# Implementation Plan: GitHub Releases Distribution

**Branch**: `002-github-releases` | **Date**: 2026-01-05 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-github-releases/spec.md`

## Summary

This feature establishes automated GitHub Releases distribution for pglogical 2.5.0, producing pre-built binaries for Windows (MSI installers + ZIP archives), Linux (tar.gz), and macOS (tar.gz for both ARM64 and x64) across PostgreSQL versions 13-18. The implementation uses GitHub Actions workflows triggered by git tags matching `v*` pattern, with WiX Toolset v5 for MSI creation. The system also provides continuous integration for pull requests and branch pushes.

## Technical Context

**Language/Version**: YAML (GitHub Actions workflows), WiX v5 (MSI definitions), Bash (install scripts), PowerShell (Windows CI), Make (existing build system)
**Primary Dependencies**: GitHub Actions runners (ubuntu-latest, windows-2022, macos-13, macos-14), WiX Toolset v5 (.NET global tool), PostgreSQL development headers, Visual Studio 2022 Build Tools, Homebrew (macOS), apt/Chocolatey (package managers)
**Storage**: N/A (artifacts stored as GitHub Release assets)
**Testing**: Regression tests via `make check` on Linux/macOS (existing Makefile infrastructure)
**Target Platform**: GitHub Actions CI/CD (builds for Windows x64, Linux x64, macOS ARM64, macOS x64)
**Project Type**: CI/CD infrastructure (workflow definitions + installer packaging)
**Performance Goals**: Complete release build within 60 minutes of tag push (SC-002)
**Constraints**: CI provides build status within 30 minutes for any PR (SC-006); fail-fast: false to allow parallel job completion
**Scale/Scope**: 30+ artifacts per release (6 PG versions × 4 platforms × artifact types)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Notes |
|-----------|------------|-------|
| I. PostgreSQL Version Compatibility | ✅ PASS | Build matrix covers PG 13-18; compat directories exist for each version |
| II. Backward Compatibility | ✅ PASS | Distribution infrastructure only; does not modify extension behavior |
| III. Testing Discipline | ✅ PASS | CI runs regression tests on Linux/macOS builds; existing test suite unchanged |
| IV. Code Quality & Memory Safety | ✅ PASS | No C code changes; uses existing Makefile build system |
| V. Replication Integrity | ✅ PASS | Distribution only; replication code path unaffected |
| VI. Implementation Completeness | ✅ PASS | Plan delivers complete working workflows, no placeholders |
| C Extension Standards | ✅ N/A | No extension code changes |
| Development Workflow | ✅ PASS | CI validates PRs; branch protection enforced |

**Gate Status**: PASS - No violations requiring justification

## Project Structure

### Documentation (this feature)

```text
specs/002-github-releases/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
.github/
└── workflows/
    ├── ci.yml               # Continuous integration (PRs + branch pushes)
    └── release.yml          # Release pipeline (tag-triggered)

packaging/
├── windows/
│   ├── pglogical.wxs        # WiX v5 MSI installer definition
│   └── README.md            # Windows installation instructions
├── unix/
│   └── install.sh           # Linux/macOS installation helper script
└── README-CI.md             # CI/CD documentation and branch protection setup
```

**Structure Decision**: CI/CD infrastructure with platform-specific packaging. Workflows live in `.github/workflows/` per GitHub Actions convention. Packaging assets organized by platform under `packaging/` directory to keep installer definitions separate from source code.

## Complexity Tracking

> No violations requiring justification - all Constitution Check gates pass.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | N/A | N/A |

## Post-Design Constitution Re-Check

*Re-evaluated after Phase 1 design completion.*

| Principle | Status | Post-Design Notes |
|-----------|--------|-------------------|
| I. PostgreSQL Version Compatibility | ✅ PASS | Build matrix includes PG 13-18; macos-14 excludes PG13 due to Homebrew availability |
| II. Backward Compatibility | ✅ PASS | MSI installer uses MajorUpgrade for clean upgrades; side-by-side installation via unique UpgradeCodes |
| III. Testing Discipline | ✅ PASS | CI workflow runs `make check` on Linux/macOS and CMake check target on Windows; all platforms run regression tests |
| IV. Code Quality & Memory Safety | ✅ PASS | No C code changes; WiX v5 and YAML are declarative |
| V. Replication Integrity | ✅ PASS | No changes to replication code paths |
| VI. Implementation Completeness | ✅ PASS | All contracts fully specified; no placeholder implementations |

**Post-Design Gate Status**: PASS - Design artifacts complete and constitution-compliant
