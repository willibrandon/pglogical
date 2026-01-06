# Research: GitHub Releases Distribution

**Date**: 2026-01-05
**Feature**: [spec.md](./spec.md)
**Status**: Complete

## Executive Summary

Research covers three critical areas for implementing GitHub Releases distribution:
1. GitHub Actions CI/CD patterns for PostgreSQL extension builds
2. WiX Toolset v5 MSI installer configuration
3. Cross-platform PostgreSQL development environment setup

All research questions resolved with specific, actionable recommendations. No NEEDS CLARIFICATION markers remain.

---

## 1. GitHub Actions CI/CD Patterns

### Decision: Dual-Workflow Architecture
**Rationale**: Separating CI (pull requests/pushes) from release (tag-triggered) workflows provides clear responsibility boundaries and prevents accidental releases.
**Alternatives Considered**:
- Single workflow with conditional jobs - rejected due to complexity and harder debugging
- Monorepo-style workflow dispatch - rejected as overkill for single project

### Build Matrix Strategy

**Decision**: Use `fail-fast: false` with explicit matrix configuration
```yaml
strategy:
  fail-fast: false
  matrix:
    pg-version: [13, 14, 15, 16, 17, 18]
    os: [ubuntu-latest, windows-2022, macos-13, macos-14]
    exclude:
      - os: macos-14
        pg-version: 13  # Homebrew may not have PG13 for ARM64
```

**Rationale**:
- `fail-fast: false` ensures all platform/version combinations complete
- Visibility into which specific jobs fail
- PostgreSQL 18 experimental builds don't block stable version results

### Submodule Configuration

**Decision**: Use HTTPS URLs with `submodules: recursive`
```yaml
- uses: actions/checkout@v4
  with:
    submodules: recursive
    fetch-depth: 0
```

**Rationale**: HTTPS URLs avoid SSH key configuration in CI; pglogical_dump submodule already uses HTTPS.

### Artifact Management

**Decision**: Use `softprops/action-gh-release@v2` for release asset upload
```yaml
- uses: softprops/action-gh-release@v2
  with:
    files: |
      pglogical-*.tar.gz
      pglogical-*.zip
      pglogical-*.msi
      checksums.txt
```

**Rationale**: Simpler than `actions/upload-release-asset@v1`; supports glob patterns; actively maintained.

---

## 2. WiX Toolset v5 MSI Configuration

### Decision: Install WiX v5 as .NET Global Tool
```yaml
- name: Install WiX v5
  run: dotnet tool install --global wix --version 5.0.0
```

**Rationale**: .NET global tool is the official distribution method for WiX v5; simplifies CI setup.

### PostgreSQL Registry Detection

**Decision**: Use `util:RegistrySearch` with bitness-aware searches
```xml
<util:RegistrySearch
  Root="HKLM"
  Id="PostgreSQL64Search"
  Key="SOFTWARE\PostgreSQL\Installations\postgresql-x64-17"
  Value="Base Directory"
  Variable="PostgreSQLInstallPath"
  Result="value"
  Bitness="always64" />
```

**Registry Paths by Version**:
- PG 13: `SOFTWARE\PostgreSQL\Installations\postgresql-x64-13`
- PG 14: `SOFTWARE\PostgreSQL\Installations\postgresql-x64-14`
- PG 15: `SOFTWARE\PostgreSQL\Installations\postgresql-x64-15`
- PG 16: `SOFTWARE\PostgreSQL\Installations\postgresql-x64-16`
- PG 17: `SOFTWARE\PostgreSQL\Installations\postgresql-x64-17`
- PG 18: `SOFTWARE\PostgreSQL\Installations\postgresql-x64-18`

### Directory Browse Fallback

**Decision**: Use WixUI_InstallDir with custom property
```xml
<UIRef Id="WixUI_InstallDir" />
<Property Id="WIXUI_INSTALLDIR" Value="POSTGRESQLDIR" />
```

**Rationale**: WiX v5 provides standard UI dialogs; avoids custom dialog authoring.

### Side-by-Side Installation

**Decision**: Use human-readable UpgradeCode per PostgreSQL version
```xml
<!-- PostgreSQL 17 version -->
<Product UpgradeCode="com.2ndquadrant.pglogical.postgresql17" ... />

<!-- PostgreSQL 16 version -->
<Product UpgradeCode="com.2ndquadrant.pglogical.postgresql16" ... />
```

**Rationale**: WiX v5 converts human-readable strings to stable GUIDs internally; easier to track and version control than raw GUIDs.

### Major Upgrade Configuration

**Decision**: Use explicit MajorUpgrade element
```xml
<MajorUpgrade
  AllowSameVersionUpgrades="yes"
  Schedule="afterInstallValidate"
  DowngradeErrorMessage="A newer version is already installed." />
```

**Rationale**: WiX v5 provides defaults, but explicit configuration ensures predictable behavior and clear downgrade handling.

---

## 3. Cross-Platform PostgreSQL Build Setup

### Ubuntu (GitHub Actions ubuntu-latest)

**Package Installation**:
```bash
sudo apt-get update
sudo apt-get install -y postgresql-server-dev-${PG_VERSION}
export PATH=/usr/lib/postgresql/${PG_VERSION}/bin:$PATH
```

**Packages by Version**:
- `postgresql-server-dev-13` through `postgresql-server-dev-18`
- Available from official PostgreSQL APT repository

### Windows (GitHub Actions windows-2022, supports Windows 10/11)

**Chocolatey Installation**:
```powershell
choco install postgresql${PG_VERSION} -y --params '/Password:postgres'
$env:PATH = "C:\Program Files\PostgreSQL\${PG_VERSION}\bin;$env:PATH"
```

**Build Approach**: Use CMake with Visual Studio 2022
```powershell
cmake -G "Visual Studio 17 2022" -DPG_CONFIG="C:\Program Files\PostgreSQL\17\bin\pg_config.exe" ..
cmake --build . --config Release
```

**Rationale**: PGXS/Make doesn't work on Windows; CMakeLists.txt already exists in pglogical.

### macOS (GitHub Actions macos-13, macos-14)

**Runner Architecture** (runner names reflect image generation, not macOS version):
- `macos-13`: x86_64 (Intel) - for macOS x64 builds (runs current macOS)
- `macos-14`: ARM64 (Apple Silicon) - for macOS ARM64 builds (runs current macOS through 26 Tahoe)

**Homebrew Installation**:
```bash
brew install postgresql@${PG_VERSION}
# Intel path
export PATH="/usr/local/opt/postgresql@${PG_VERSION}/bin:$PATH"
# ARM64 path (macos-14)
export PATH="/opt/homebrew/opt/postgresql@${PG_VERSION}/bin:$PATH"
```

### pg_config Usage

**Installation Script Pattern**:
```bash
#!/bin/bash
set -e
PKGLIBDIR=$(pg_config --pkglibdir)
SHAREDIR=$(pg_config --sharedir)

install -m755 pglogical.so "$PKGLIBDIR/"
install -m755 pglogical_output.so "$PKGLIBDIR/"
install -m644 pglogical.control "$SHAREDIR/extension/"
install -m644 pglogical--*.sql "$SHAREDIR/extension/"
```

**Paths by Platform**:
| Platform | pkglibdir | sharedir/extension |
|----------|-----------|-------------------|
| Linux | `/usr/lib/postgresql/17/lib` | `/usr/share/postgresql/17/extension` |
| macOS Intel | `/usr/local/opt/postgresql@17/lib` | `/usr/local/opt/postgresql@17/share/extension` |
| macOS ARM64 | `/opt/homebrew/opt/postgresql@17/lib` | `/opt/homebrew/opt/postgresql@17/share/extension` |
| Windows | `C:\Program Files\PostgreSQL\17\lib` | `C:\Program Files\PostgreSQL\17\share\extension` |

---

## 4. Artifact Naming Convention

**Decision**: Follow pattern `pglogical-{version}-pg{pg_version}-{platform}-{arch}.{ext}`

**Examples**:
- `pglogical-2.5.0-pg17-linux-x64.tar.gz`
- `pglogical-2.5.0-pg17-windows-x64.zip`
- `pglogical-2.5.0-pg17-windows-x64.msi`
- `pglogical-2.5.0-pg17-macos-arm64.tar.gz`
- `pglogical-2.5.0-pg17-macos-x64.tar.gz`
- `pglogical-2.5.0-source.tar.gz`

**Version Extraction**: Strip `v` prefix from git tag
```bash
VERSION=${GITHUB_REF_NAME#v}  # v2.5.0 -> 2.5.0
```

---

## 5. Prerelease Detection

**Decision**: Mark releases as prerelease if tag contains hyphen
```yaml
- name: Create Release
  uses: softprops/action-gh-release@v2
  with:
    prerelease: ${{ contains(github.ref_name, '-') }}
```

**Examples**:
- `v2.5.0` → release
- `v2.5.0-beta1` → prerelease
- `v2.5.0-rc1` → prerelease

---

## Sources

### GitHub Actions
- [adjust/pg-ext-actions](https://github.com/adjust/pg-ext-actions)
- [softprops/action-gh-release](https://github.com/softprops/action-gh-release)
- [GitHub Actions Matrix Strategy](https://docs.github.com/en/actions/using-jobs/using-a-matrix-for-your-jobs)
- [GitHub Actions checkout@v4](https://github.com/actions/checkout)

### WiX Toolset v5
- [WiX Toolset Documentation](https://wixtoolset.org/docs/)
- [FireGiant WiX Schema Reference](https://docs.firegiant.com/wix/schema/)
- [WiX v5 RegistrySearch](https://docs.firegiant.com/wix/schema/util/registrysearch/)
- [WiX v5 MajorUpgrade](https://docs.firegiant.com/wix/schema/wxs/majorupgrade/)

### PostgreSQL
- [PostgreSQL APT Repository](https://wiki.postgresql.org/wiki/Apt)
- [Chocolatey PostgreSQL Packages](https://community.chocolatey.org/packages/postgresql)
- [PostgreSQL PGXS Documentation](https://www.postgresql.org/docs/current/extend-pgxs.html)
- [pg_config Reference](https://www.postgresql.org/docs/current/app-pgconfig.html)
