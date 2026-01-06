# Data Model: GitHub Releases Distribution

**Date**: 2026-01-05
**Feature**: [spec.md](./spec.md)

## Overview

This feature is CI/CD infrastructure with no persistent application data model. The "entities" are conceptual workflow artifacts and configurations, not database entities.

## Key Entities

### 1. Release Artifact

A downloadable file attached to a GitHub Release.

**Attributes**:
| Attribute | Type | Description |
|-----------|------|-------------|
| filename | string | Full artifact name following naming convention |
| version | string | pglogical version (e.g., "2.5.0") |
| pg_version | integer | PostgreSQL major version (13-18) |
| platform | enum | "windows", "linux", "macos" |
| arch | enum | "x64", "arm64" |
| format | enum | "zip", "tar.gz", "msi" |
| sha256 | string | SHA256 checksum |

**Naming Pattern**: `pglogical-{version}-pg{pg_version}-{platform}-{arch}.{format}`

**Validation Rules**:
- Version must follow semantic versioning (major.minor.patch)
- pg_version must be in supported range (13-18)
- Platform/arch combinations must be valid (no Windows ARM64, no Linux ARM64)

### 2. Build Matrix Entry

A single build configuration in the CI/CD matrix.

**Attributes**:
| Attribute | Type | Description |
|-----------|------|-------------|
| os | string | GitHub Actions runner (ubuntu-latest, windows-2022, macos-13, macos-14) |
| pg_version | integer | PostgreSQL major version |
| arch | string | Derived from runner (x64 or arm64) |
| compiler | string | Derived from platform (gcc, msvc, clang) |

**Valid Combinations**:
| Runner | Architecture | PostgreSQL Versions |
|--------|--------------|---------------------|
| ubuntu-latest | x64 | 13, 14, 15, 16, 17, 18 |
| windows-2022 | x64 | 13, 14, 15, 16, 17, 18 |
| macos-13 | x64 | 13, 14, 15, 16, 17, 18 |
| macos-14 | arm64 | 14, 15, 16, 17, 18 |

**Notes**:
- windows-2022 runner builds are compatible with Windows 10 and Windows 11 (builds on Windows Server 2022)
- macos-14 excludes PG13 as Homebrew may not provide it for ARM64
- PG18 may have delayed availability on Homebrew for new releases; CI uses `fail-fast: false` to handle gracefully

### 3. GitHub Release

A tagged release on GitHub containing release notes and artifacts.

**Attributes**:
| Attribute | Type | Description |
|-----------|------|-------------|
| tag_name | string | Git tag (e.g., "v2.5.0") |
| name | string | Release title (e.g., "pglogical 2.5.0") |
| body | string | Release notes with installation instructions |
| prerelease | boolean | True if tag contains hyphen (e.g., "-beta1") |
| draft | boolean | Always false (published immediately) |
| assets | array | List of Release Artifacts |

**State Transitions**:
```
[Tag Push] → [Builds Running] → [All Builds Complete] → [Release Created] → [Assets Attached]
```

### 4. MSI Installer Configuration

WiX v5 installer configuration for Windows.

**Attributes**:
| Attribute | Type | Description |
|-----------|------|-------------|
| product_name | string | "pglogical for PostgreSQL {pg_version}" |
| version | string | 4-part version (e.g., "2.5.0.0") |
| manufacturer | string | "2ndQuadrant" |
| upgrade_code | string | Human-readable ID per PG version |
| install_dir | path | Detected or user-selected PostgreSQL directory |

**UpgradeCode Pattern**:
- PG 13: `com.2ndquadrant.pglogical.postgresql13`
- PG 14: `com.2ndquadrant.pglogical.postgresql14`
- PG 15: `com.2ndquadrant.pglogical.postgresql15`
- PG 16: `com.2ndquadrant.pglogical.postgresql16`
- PG 17: `com.2ndquadrant.pglogical.postgresql17`
- PG 18: `com.2ndquadrant.pglogical.postgresql18`

**Validation Rules**:
- Same UpgradeCode = versions upgrade each other
- Different UpgradeCode = side-by-side installation allowed

### 5. Workflow Configuration

GitHub Actions workflow definition.

**CI Workflow Triggers**:
| Event | Target |
|-------|--------|
| push | REL2_x_STABLE, windows-build branches |
| pull_request | REL2_x_STABLE branch |

**Release Workflow Triggers**:
| Event | Pattern |
|-------|---------|
| push (tags) | v* |

## Relationships

```
GitHub Release (1) ───────── (*) Release Artifact
       │
       └──── contains checksums.txt with all artifact hashes

Build Matrix Entry (*) ───── (1) Release Artifact
       │
       └──── each matrix entry produces one or more artifacts

MSI Installer Configuration (1) ───── (1) Release Artifact (MSI)
       │
       └──── one MSI per PostgreSQL version
```

## File Outputs

### Artifacts per Build

| Platform | Artifacts Produced |
|----------|-------------------|
| Linux | `pglogical-{ver}-pg{pg}-linux-x64.tar.gz` |
| Windows | `pglogical-{ver}-pg{pg}-windows-x64.zip`, `pglogical-{ver}-pg{pg}-windows-x64.msi` |
| macOS x64 | `pglogical-{ver}-pg{pg}-macos-x64.tar.gz` |
| macOS ARM64 | `pglogical-{ver}-pg{pg}-macos-arm64.tar.gz` |

### Source Archives

- `pglogical-{version}-source.tar.gz`
- `pglogical-{version}-source.zip`

### Checksum File

`checksums.txt` containing:
```
<sha256>  pglogical-2.5.0-pg17-linux-x64.tar.gz
<sha256>  pglogical-2.5.0-pg17-windows-x64.zip
<sha256>  pglogical-2.5.0-pg17-windows-x64.msi
...
```
