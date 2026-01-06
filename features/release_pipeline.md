# pglogical Release Pipeline Feature

**Target**: pglogical 2.5.0
**Author**: Brandon
**Status**: Design Proposal

## Overview

Establish a comprehensive build, test, and release pipeline for pglogical that supports multiple PostgreSQL versions (13-18) across Windows, Linux, and macOS. Distribution channels include PGXN, GitHub Releases, Winget, and Homebrew.

## Problem Statement

Currently, pglogical lacks:
1. Automated CI/CD pipeline for cross-platform builds
2. Pre-built binary distribution for Windows users
3. Package manager integration (Winget, Homebrew)
4. Streamlined release process for multiple PostgreSQL versions
5. Automated regression testing across platforms

## Solution

Implement a GitHub Actions-based pipeline that:
1. Builds and tests on push/PR for all supported platforms
2. Creates versioned releases with pre-built binaries
3. Generates WiX installers for Windows (one per PG version)
4. Publishes to PGXN, Winget, and Homebrew

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         GitHub Actions Workflow                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  on: push/PR                              on: release (tag v*)          │
│       │                                          │                      │
│       ▼                                          ▼                      │
│  ┌─────────────┐                        ┌─────────────────────┐        │
│  │ CI Pipeline │                        │  Release Pipeline   │        │
│  │             │                        │                     │        │
│  │ - Build     │                        │ - Build all targets │        │
│  │ - Test      │                        │ - Create installers │        │
│  │ - Lint      │                        │ - Upload artifacts  │        │
│  └─────────────┘                        │ - Publish PGXN      │        │
│                                         │ - Update Winget     │        │
│                                         │ - Update Homebrew   │        │
│                                         └─────────────────────┘        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

Build Matrix:
┌──────────────────────────────────────────────────────────────────────────┐
│                    PostgreSQL Versions: 13, 14, 15, 16, 17, 18          │
├───────────────┬───────────────┬───────────────┬──────────────────────────┤
│    Windows    │     Linux     │     macOS     │       Output             │
│   (MSVC/CMake)│   (Makefile)  │   (Makefile)  │                          │
├───────────────┼───────────────┼───────────────┼──────────────────────────┤
│ pglogical.dll │ pglogical.so  │ pglogical.dylib│ + SQL extension files   │
│ + MSI installer│ (source pkg) │ (Homebrew)    │                          │
└───────────────┴───────────────┴───────────────┴──────────────────────────┘
```

## Distribution Channels

### 1. GitHub Releases (Primary)

Pre-built binaries organized by PostgreSQL version:

```
pglogical-2.5.0/
├── pglogical-2.5.0-pg18-windows-x64.zip
├── pglogical-2.5.0-pg18-windows-x64.msi
├── pglogical-2.5.0-pg17-windows-x64.zip
├── pglogical-2.5.0-pg17-windows-x64.msi
├── pglogical-2.5.0-pg16-windows-x64.zip
├── pglogical-2.5.0-pg16-windows-x64.msi
├── pglogical-2.5.0-pg15-windows-x64.zip
├── pglogical-2.5.0-pg15-windows-x64.msi
├── pglogical-2.5.0-pg14-windows-x64.zip
├── pglogical-2.5.0-pg14-windows-x64.msi
├── pglogical-2.5.0-pg13-windows-x64.zip
├── pglogical-2.5.0-pg13-windows-x64.msi
├── pglogical-2.5.0-source.tar.gz
└── pglogical-2.5.0-source.zip
```

### 2. PGXN (PostgreSQL Extension Network)

Source distribution for discoverability in the PostgreSQL ecosystem.

**META.json** (new file):
```json
{
   "name": "pglogical",
   "abstract": "PostgreSQL Logical Replication",
   "description": "Fully asynchronous logical replication extension providing bidirectional replication and conflict resolution",
   "version": "2.5.0",
   "maintainer": "willibrandon <willibrandon@users.noreply.github.com>",
   "license": "postgresql",
   "provides": {
      "pglogical": {
         "abstract": "PostgreSQL Logical Replication",
         "file": "pglogical.control",
         "version": "2.5.0"
      }
   },
   "prereqs": {
      "runtime": {
         "requires": {
            "PostgreSQL": "13.0.0"
         }
      }
   },
   "resources": {
      "bugtracker": {
         "web": "https://github.com/willibrandon/pglogical/issues"
      },
      "repository": {
         "url": "https://github.com/willibrandon/pglogical.git",
         "web": "https://github.com/willibrandon/pglogical",
         "type": "git"
      }
   },
   "generated_by": "willibrandon",
   "meta-spec": {
      "version": "1.0.0",
      "url": "https://pgxn.org/meta/spec.txt"
   },
   "tags": [
      "replication",
      "logical replication",
      "bidirectional",
      "multi-master",
      "conflict resolution"
   ]
}
```

### 3. Winget (Windows Package Manager)

Separate packages per PostgreSQL version for precise installation:

**Package identifiers:**
- `willibrandon.pglogical.pg18`
- `willibrandon.pglogical.pg17`
- `willibrandon.pglogical.pg16`
- `willibrandon.pglogical.pg15`
- `willibrandon.pglogical.pg14`
- `willibrandon.pglogical.pg13`

### 4. Homebrew (macOS)

Formula that builds from source with PostgreSQL dependency:

```ruby
class Pglogical < Formula
  desc "PostgreSQL logical replication extension"
  homepage "https://github.com/willibrandon/pglogical"
  url "https://github.com/willibrandon/pglogical/archive/refs/tags/v2.5.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "PostgreSQL"

  depends_on "postgresql@17"

  def install
    ENV["PG_CONFIG"] = Formula["postgresql@17"].opt_bin/"pg_config"
    system "make", "clean", "all"
    system "make", "install", "DESTDIR=#{buildpath}/stage"

    # Copy to Homebrew's PostgreSQL extension directory
    lib.install Dir["stage/**/pglogical*.so"]
    share.install Dir["stage/**/extension/*"]
  end

  test do
    system "pg_config", "--version"
  end
end
```

## Submodule Handling

pglogical includes the `pglogical_dump` submodule which requires special handling:

### Issue: SSH URL in .gitmodules

The current `.gitmodules` uses an SSH URL:
```ini
[submodule "pglogical_dump"]
    path = pglogical_dump
    url = git@github.com:2ndQuadrant/pglogical_dump.git
```

GitHub Actions cannot authenticate to SSH URLs without SSH key configuration. Two options:

**Option A: Change .gitmodules to HTTPS (Recommended)**
```ini
[submodule "pglogical_dump"]
    path = pglogical_dump
    url = https://github.com/2ndQuadrant/pglogical_dump.git
```

**Option B: Configure URL replacement in workflows**
```yaml
- name: Configure git for HTTPS submodules
  run: |
    git config --global url."https://github.com/".insteadOf "git@github.com:"
```

### Issue: Source Tarball Creation

`git archive` does not include submodule contents. Use `git-archive-all` or manual bundling:

```yaml
- name: Create source tarball with submodules
  run: |
    VERSION="${{ env.VERSION }}"
    VERSION="${VERSION#v}"

    # Initialize and update submodules
    git submodule update --init --recursive

    # Create tarball with submodule contents
    pip install git-archive-all
    git-archive-all --prefix=pglogical-$VERSION/ pglogical-$VERSION-source.tar.gz

    # Or manually:
    # git archive --prefix=pglogical-$VERSION/ HEAD > pglogical-$VERSION.tar
    # cd pglogical_dump && git archive --prefix=pglogical-$VERSION/pglogical_dump/ HEAD > ../dump.tar
    # tar --concatenate --file=pglogical-$VERSION.tar ../dump.tar
    # gzip pglogical-$VERSION.tar
```

### Pre-release Checklist Addition

Before releasing, ensure:
- [ ] `.gitmodules` uses HTTPS URL (not SSH)
- [ ] Submodule is at the correct commit
- [ ] Source tarball includes submodule contents

## Implementation

### 1. GitHub Actions Workflows

#### `.github/workflows/ci.yml` - Continuous Integration

```yaml
name: CI

on:
  push:
    branches: [REL2_x_STABLE, windows-build]
  pull_request:
    branches: [REL2_x_STABLE]

jobs:
  build-linux:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        pg_version: [13, 14, 15, 16, 17, 18]
    steps:
      - name: Configure git for HTTPS submodules
        run: git config --global url."https://github.com/".insteadOf "git@github.com:"

      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install PostgreSQL ${{ matrix.pg_version }}
        run: |
          sudo apt-get update
          sudo apt-get install -y postgresql-${{ matrix.pg_version }} \
            postgresql-server-dev-${{ matrix.pg_version }}
          echo "/usr/lib/postgresql/${{ matrix.pg_version }}/bin" >> $GITHUB_PATH

      - name: Build pglogical
        run: |
          make clean all PG_CONFIG=/usr/lib/postgresql/${{ matrix.pg_version }}/bin/pg_config

      - name: Install pglogical
        run: |
          sudo make install PG_CONFIG=/usr/lib/postgresql/${{ matrix.pg_version }}/bin/pg_config

      - name: Run regression tests
        run: |
          make check PG_CONFIG=/usr/lib/postgresql/${{ matrix.pg_version }}/bin/pg_config

  build-windows:
    runs-on: windows-latest
    strategy:
      fail-fast: false
      matrix:
        pg_version: [14, 15, 16, 17]
    steps:
      - name: Configure git for HTTPS submodules
        run: git config --global url."https://github.com/".insteadOf "git@github.com:"

      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install PostgreSQL ${{ matrix.pg_version }}
        run: |
          choco install postgresql${{ matrix.pg_version }} --params '/Password:postgres' -y
          echo "C:\Program Files\PostgreSQL\${{ matrix.pg_version }}\bin" | Out-File -Append $env:GITHUB_PATH

      - name: Configure CMake
        run: |
          cmake -B build -S . -G "Visual Studio 17 2022" -A x64 `
            -DCMAKE_BUILD_TYPE=Release

      - name: Build
        run: cmake --build build --config Release

      - name: Upload build artifacts
        uses: actions/upload-artifact@v4
        with:
          name: pglogical-pg${{ matrix.pg_version }}-windows
          path: |
            build/Release/*.dll
            *.sql
            *.control

  build-macos:
    runs-on: macos-latest
    strategy:
      fail-fast: false
      matrix:
        pg_version: [15, 16, 17]
    steps:
      - name: Configure git for HTTPS submodules
        run: git config --global url."https://github.com/".insteadOf "git@github.com:"

      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install PostgreSQL ${{ matrix.pg_version }}
        run: |
          brew install postgresql@${{ matrix.pg_version }}
          echo "$(brew --prefix postgresql@${{ matrix.pg_version }})/bin" >> $GITHUB_PATH

      - name: Build pglogical
        run: make clean all

      - name: Run regression tests
        run: make check
```

#### `.github/workflows/release.yml` - Release Pipeline

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

env:
  VERSION: ${{ github.ref_name }}

jobs:
  build-windows-installers:
    runs-on: windows-latest
    strategy:
      fail-fast: false
      matrix:
        pg_version: [13, 14, 15, 16, 17, 18]
    steps:
      - name: Configure git for HTTPS submodules
        run: git config --global url."https://github.com/".insteadOf "git@github.com:"

      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install PostgreSQL ${{ matrix.pg_version }}
        run: |
          choco install postgresql${{ matrix.pg_version }} --params '/Password:postgres' -y

      - name: Configure CMake
        run: |
          $PG_ROOT = "C:\Program Files\PostgreSQL\${{ matrix.pg_version }}"
          cmake -B build -S . -G "Visual Studio 17 2022" -A x64 `
            -DCMAKE_BUILD_TYPE=Release `
            -DPostgreSQL_ROOT="$PG_ROOT"

      - name: Build
        run: cmake --build build --config Release

      - name: Prepare package directory
        run: |
          $VERSION = "${{ env.VERSION }}".TrimStart('v')
          $PG_VER = "${{ matrix.pg_version }}"
          mkdir -p package/lib
          mkdir -p package/share/extension

          # Copy DLL
          Copy-Item build/Release/pglogical.dll package/lib/
          Copy-Item build/Release/pglogical_output.dll package/lib/

          # Copy SQL and control files
          Copy-Item *.control package/share/extension/
          Copy-Item pglogical--*.sql package/share/extension/

      - name: Create ZIP archive
        run: |
          $VERSION = "${{ env.VERSION }}".TrimStart('v')
          Compress-Archive -Path package/* `
            -DestinationPath "pglogical-$VERSION-pg${{ matrix.pg_version }}-windows-x64.zip"

      - name: Install WiX Toolset
        run: dotnet tool install --global wix

      - name: Build MSI installer
        run: |
          $VERSION = "${{ env.VERSION }}".TrimStart('v')
          wix build wix/pglogical.wxs `
            -d Version=$VERSION `
            -d PgVersion=${{ matrix.pg_version }} `
            -d SourceDir=package `
            -o "pglogical-$VERSION-pg${{ matrix.pg_version }}-windows-x64.msi"

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: windows-pg${{ matrix.pg_version }}
          path: |
            *.zip
            *.msi

  build-source-package:
    runs-on: ubuntu-latest
    steps:
      - name: Configure git for HTTPS submodules
        run: git config --global url."https://github.com/".insteadOf "git@github.com:"

      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Create source tarball with submodules
        run: |
          VERSION="${{ env.VERSION }}"
          VERSION="${VERSION#v}"

          # Install git-archive-all to include submodule contents
          pip install git-archive-all

          # Create tarball and zip with submodule contents included
          git-archive-all --prefix=pglogical-$VERSION/ pglogical-$VERSION-source.tar.gz
          git-archive-all --prefix=pglogical-$VERSION/ pglogical-$VERSION-source.zip

      - name: Upload source packages
        uses: actions/upload-artifact@v4
        with:
          name: source-packages
          path: |
            *.tar.gz
            *.zip

  create-release:
    needs: [build-windows-installers, build-source-package]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: artifacts

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          name: pglogical ${{ env.VERSION }}
          body: |
            ## pglogical ${{ env.VERSION }}

            ### Installation

            **Windows (MSI installer):**
            Download the MSI for your PostgreSQL version and run. The installer will:
            - Detect PostgreSQL installation via `pg_config` (if in PATH)
            - Allow manual specification of PostgreSQL installation path
            - Install extension files to the correct locations

            **Windows (Manual):**
            1. Download the ZIP for your PostgreSQL version
            2. Copy `lib/*.dll` to your PostgreSQL `lib` directory
            3. Copy `share/extension/*` to your PostgreSQL `share/extension` directory
            4. Run: `CREATE EXTENSION pglogical;`

            **Linux/macOS (from source):**
            ```bash
            tar xzf pglogical-${{ env.VERSION }}-source.tar.gz
            cd pglogical-*
            make && sudo make install
            ```

            **Winget:**
            ```powershell
            winget install willibrandon.pglogical.pg17  # For PostgreSQL 17
            ```

            **Homebrew:**
            ```bash
            brew install willibrandon/tap/pglogical
            ```

            ### Changes
            See [CHANGELOG.md](CHANGELOG.md) for details.
          files: |
            artifacts/**/*.zip
            artifacts/**/*.msi
            artifacts/**/*.tar.gz
          draft: false
          prerelease: false

  publish-pgxn:
    needs: [create-release]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install PGXN client
        run: pip install pgxnclient

      - name: Create PGXN distribution
        run: |
          VERSION="${{ env.VERSION }}"
          VERSION="${VERSION#v}"
          # Create distribution zip with META.json
          zip -r pglogical-$VERSION.zip . -x ".git/*" -x "build/*"

      - name: Publish to PGXN
        env:
          PGXN_USERNAME: ${{ secrets.PGXN_USERNAME }}
          PGXN_PASSWORD: ${{ secrets.PGXN_PASSWORD }}
        run: |
          VERSION="${{ env.VERSION }}"
          VERSION="${VERSION#v}"
          pgxn upload pglogical-$VERSION.zip

  update-winget:
    needs: [create-release]
    runs-on: ubuntu-latest
    strategy:
      matrix:
        pg_version: [13, 14, 15, 16, 17, 18]
    steps:
      - uses: actions/checkout@v4

      - name: Download MSI artifact
        uses: actions/download-artifact@v4
        with:
          name: windows-pg${{ matrix.pg_version }}
          path: artifacts

      - name: Calculate SHA256
        id: sha
        run: |
          VERSION="${{ env.VERSION }}"
          VERSION="${VERSION#v}"
          SHA=$(sha256sum artifacts/pglogical-$VERSION-pg${{ matrix.pg_version }}-windows-x64.msi | cut -d' ' -f1)
          echo "sha256=$SHA" >> $GITHUB_OUTPUT

      - name: Update Winget manifests
        run: |
          VERSION="${{ env.VERSION }}"
          VERSION="${VERSION#v}"
          PG_VER="${{ matrix.pg_version }}"

          # Update template manifests with actual values
          sed -i "s/PLACEHOLDER_VERSION/$VERSION/g" winget/templates/*.yaml
          sed -i "s/PLACEHOLDER_PG_VERSION/$PG_VER/g" winget/templates/*.yaml
          sed -i "s/PLACEHOLDER_SHA256/${{ steps.sha.outputs.sha256 }}/g" winget/templates/*.yaml

      - name: Submit to winget-pkgs
        uses: vedantmgoyal2009/winget-releaser@v2
        with:
          identifier: willibrandon.pglogical.pg${{ matrix.pg_version }}
          version: ${{ env.VERSION }}
          installers-regex: 'pglogical-.*-pg${{ matrix.pg_version }}-windows-x64\.msi$'
          token: ${{ secrets.WINGET_TOKEN }}

  update-homebrew:
    needs: [create-release]
    runs-on: ubuntu-latest
    steps:
      - name: Update Homebrew tap
        uses: mislav/bump-homebrew-formula-action@v3
        with:
          formula-name: pglogical
          homebrew-tap: willibrandon/homebrew-tap
          download-url: https://github.com/willibrandon/pglogical/archive/refs/tags/${{ env.VERSION }}.tar.gz
        env:
          COMMITTER_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}
```

### 2. WiX Installer

#### `wix/pglogical.wxs`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!--
  pglogical Windows Installer (WiX v5)

  Build parameters:
    -d Version=2.5.0
    -d PgVersion=17
    -d SourceDir=path/to/files
-->
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs"
     xmlns:ui="http://wixtoolset.org/schemas/v4/wxs/ui">

  <Package Name="pglogical for PostgreSQL $(var.PgVersion)"
           Version="$(var.Version).0"
           Manufacturer="willibrandon"
           UpgradeCode="A1B2C3D4-E5F6-7890-ABCD-$(var.PgVersion)00000000"
           Scope="perMachine">

    <SummaryInformation Description="PostgreSQL Logical Replication Extension for PostgreSQL $(var.PgVersion)" />

    <MajorUpgrade DowngradeErrorMessage="A newer version of pglogical for PostgreSQL $(var.PgVersion) is already installed."
                  AllowSameVersionUpgrades="yes" />

    <MediaTemplate EmbedCab="yes" CompressionLevel="high" />

    <!-- Properties -->
    <Property Id="PGINSTALLDIR" Secure="yes">
      <RegistrySearch Id="PgInstallDirSearch"
                      Root="HKLM"
                      Key="SOFTWARE\PostgreSQL\Installations\postgresql-x64-$(var.PgVersion)"
                      Name="Base Directory"
                      Type="directory" />
    </Property>

    <!-- Try pg_config if registry lookup fails -->
    <SetProperty Id="PGINSTALLDIR"
                 Value="[%ProgramFiles]\PostgreSQL\$(var.PgVersion)"
                 Before="CostFinalize"
                 Condition="NOT PGINSTALLDIR" />

    <!-- UI for path selection -->
    <ui:WixUI Id="WixUI_InstallDir" InstallDirectory="PGINSTALLDIR" />

    <!-- Installation directories -->
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="PGINSTALLDIR">
        <Directory Id="LIBDIR" Name="lib" />
        <Directory Id="SHAREDIR" Name="share">
          <Directory Id="EXTENSIONDIR" Name="extension" />
        </Directory>
      </Directory>
    </Directory>

    <!-- DLL component -->
    <ComponentGroup Id="DllComponents" Directory="LIBDIR">
      <Component Id="pglogical_dll" Guid="B2C3D4E5-F6A7-8901-BCDE-$(var.PgVersion)11111111">
        <File Source="$(var.SourceDir)\lib\pglogical.dll" />
      </Component>
      <Component Id="pglogical_output_dll" Guid="C3D4E5F6-A7B8-9012-CDEF-$(var.PgVersion)22222222">
        <File Source="$(var.SourceDir)\lib\pglogical_output.dll" />
      </Component>
    </ComponentGroup>

    <!-- Extension files component -->
    <ComponentGroup Id="ExtensionComponents" Directory="EXTENSIONDIR">
      <Component Id="control_file" Guid="D4E5F6A7-B890-1234-DEFG-$(var.PgVersion)33333333">
        <File Source="$(var.SourceDir)\share\extension\pglogical.control" />
      </Component>
      <Component Id="sql_files" Guid="E5F6A7B8-9012-3456-EFGH-$(var.PgVersion)44444444">
        <Files Include="$(var.SourceDir)\share\extension\pglogical--*.sql" />
      </Component>
    </ComponentGroup>

    <!-- Main feature -->
    <Feature Id="MainFeature" Title="pglogical" Level="1">
      <ComponentGroupRef Id="DllComponents" />
      <ComponentGroupRef Id="ExtensionComponents" />
    </Feature>

    <!-- Custom action to detect pg_config -->
    <CustomAction Id="DetectPgConfig"
                  Directory="TARGETDIR"
                  ExeCommand="[SystemFolder]cmd.exe /c pg_config --bindir"
                  Execute="immediate"
                  Return="ignore" />

  </Package>
</Wix>
```

### 3. Winget Manifest Templates

#### `winget/templates/willibrandon.pglogical.pgXX.yaml`

```yaml
# yaml-language-server: $schema=https://aka.ms/winget-manifest.version.1.9.0.schema.json
PackageIdentifier: willibrandon.pglogical.pgPLACEHOLDER_PG_VERSION
PackageVersion: PLACEHOLDER_VERSION
DefaultLocale: en-US
ManifestType: version
ManifestVersion: 1.9.0
```

#### `winget/templates/willibrandon.pglogical.pgXX.installer.yaml`

```yaml
# yaml-language-server: $schema=https://aka.ms/winget-manifest.installer.1.9.0.schema.json
PackageIdentifier: willibrandon.pglogical.pgPLACEHOLDER_PG_VERSION
PackageVersion: PLACEHOLDER_VERSION
Platform:
  - Windows.Desktop
MinimumOSVersion: 10.0.18362.0
InstallerType: msi
Scope: machine
InstallModes:
  - interactive
  - silent
  - silentWithProgress
UpgradeBehavior: install
Dependencies:
  PackageDependencies:
    - PackageIdentifier: PostgreSQL.PostgreSQL.PLACEHOLDER_PG_VERSION
Installers:
  - Architecture: x64
    InstallerUrl: https://github.com/willibrandon/pglogical/releases/download/vPLACEHOLDER_VERSION/pglogical-PLACEHOLDER_VERSION-pgPLACEHOLDER_PG_VERSION-windows-x64.msi
    InstallerSha256: PLACEHOLDER_SHA256
ManifestType: installer
ManifestVersion: 1.9.0
```

#### `winget/templates/willibrandon.pglogical.pgXX.locale.en-US.yaml`

```yaml
# yaml-language-server: $schema=https://aka.ms/winget-manifest.defaultLocale.1.9.0.schema.json
PackageIdentifier: willibrandon.pglogical.pgPLACEHOLDER_PG_VERSION
PackageVersion: PLACEHOLDER_VERSION
PackageLocale: en-US
Publisher: willibrandon
PublisherUrl: https://github.com/willibrandon
PublisherSupportUrl: https://github.com/willibrandon/pglogical/issues
PackageName: pglogical for PostgreSQL PLACEHOLDER_PG_VERSION
PackageUrl: https://github.com/willibrandon/pglogical
License: PostgreSQL License
LicenseUrl: https://github.com/willibrandon/pglogical/blob/REL2_x_STABLE/LICENSE
ShortDescription: PostgreSQL logical replication extension
Description: |
  pglogical is a PostgreSQL extension that provides fully asynchronous logical replication.
  Features include:
  - Bidirectional (multi-master) replication
  - Selective table replication via replication sets
  - Conflict detection and resolution
  - Conflict history tracking
  - Initial data synchronization
Tags:
  - postgresql
  - replication
  - database
  - extension
  - logical-replication
ManifestType: defaultLocale
ManifestVersion: 1.9.0
```

### 4. Homebrew Formula

#### `homebrew/pglogical.rb`

```ruby
class Pglogical < Formula
  desc "PostgreSQL logical replication extension with bidirectional support"
  homepage "https://github.com/willibrandon/pglogical"
  url "https://github.com/willibrandon/pglogical/archive/refs/tags/v2.5.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "PostgreSQL"
  head "https://github.com/willibrandon/pglogical.git", branch: "REL2_x_STABLE"

  depends_on "postgresql@17"

  def postgresql
    Formula["postgresql@17"]
  end

  def install
    ENV["PG_CONFIG"] = postgresql.opt_bin/"pg_config"

    # Build using Makefile
    system "make", "clean"
    system "make", "all", "PG_CONFIG=#{ENV["PG_CONFIG"]}"

    # Install to staging directory
    system "make", "install", "DESTDIR=#{buildpath}/stage", "PG_CONFIG=#{ENV["PG_CONFIG"]}"

    # Get PostgreSQL directories
    pkglibdir = `#{ENV["PG_CONFIG"]} --pkglibdir`.chomp
    sharedir = `#{ENV["PG_CONFIG"]} --sharedir`.chomp

    # Copy to formula prefix (Homebrew will symlink to PostgreSQL)
    (lib/"postgresql").install Dir["stage#{pkglibdir}/*.dylib"]
    (share/"postgresql/extension").install Dir["stage#{sharedir}/extension/*"]
  end

  def caveats
    <<~EOS
      To enable pglogical, add to your postgresql.conf:
        shared_preload_libraries = 'pglogical'
        wal_level = 'logical'
        max_worker_processes = 10
        max_replication_slots = 10
        max_wal_senders = 10

      Then restart PostgreSQL and run:
        CREATE EXTENSION pglogical;
    EOS
  end

  test do
    system postgresql.opt_bin/"pg_config", "--version"
  end
end
```

### 5. Directory Structure

```
pglogical/
├── .github/
│   └── workflows/
│       ├── ci.yml           # CI on push/PR
│       └── release.yml      # Release pipeline
├── wix/
│   └── pglogical.wxs        # WiX installer definition
├── winget/
│   ├── templates/           # Manifest templates
│   │   ├── willibrandon.pglogical.pgXX.yaml
│   │   ├── willibrandon.pglogical.pgXX.installer.yaml
│   │   └── willibrandon.pglogical.pgXX.locale.en-US.yaml
│   └── README.md            # Winget submission instructions
├── homebrew/
│   └── pglogical.rb         # Homebrew formula
├── META.json                # PGXN metadata
└── ...
```

## Configuration

### GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `PGXN_USERNAME` | PGXN account username |
| `PGXN_PASSWORD` | PGXN account password |
| `WINGET_TOKEN` | GitHub PAT for winget-pkgs PR |
| `HOMEBREW_TAP_TOKEN` | GitHub PAT for homebrew-tap updates |

### Repository Settings

1. Enable GitHub Actions
2. Configure branch protection for `REL2_x_STABLE`
3. Set up tag-based releases (format: `v2.5.0`)

## Release Process

### Pre-release Checklist

1. Update version in:
   - `pglogical.control`
   - `META.json`
   - `CMakeLists.txt`
2. Create/update upgrade SQL script (`pglogical--2.4.6--2.5.0.sql`)
3. Update `CHANGELOG.md`
4. Verify submodule setup:
   - `.gitmodules` uses HTTPS URL (not SSH)
   - Submodule is at the correct commit (`git submodule status`)
5. Ensure all tests pass on CI
6. Tag release: `git tag v2.5.0 && git push --tags`

### Automated Steps (on tag push)

1. Build Windows MSI installers (PG 13-18)
2. Build source packages
3. Create GitHub Release with all artifacts
4. Publish to PGXN
5. Submit Winget manifest PRs
6. Update Homebrew tap

### Post-release Verification

1. Verify GitHub Release artifacts
2. Test MSI installation on fresh Windows VM
3. Verify PGXN listing
4. Verify `winget search pglogical` (after PR merge)
5. Verify `brew install willibrandon/tap/pglogical`

## Homebrew Tap Changes (willibrandon/homebrew-tap)

The existing `willibrandon/homebrew-tap` repository needs the following changes to support pglogical.

### New Files

#### `Formula/pglogical.rb`

```ruby
# typed: false
# frozen_string_literal: true

# Homebrew formula for pglogical - PostgreSQL logical replication extension
# Builds from source against the installed PostgreSQL version
class Pglogical < Formula
  desc "PostgreSQL logical replication extension with bidirectional support"
  homepage "https://github.com/willibrandon/pglogical"
  url "https://github.com/willibrandon/pglogical/archive/refs/tags/v2.5.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "PostgreSQL"
  head "https://github.com/willibrandon/pglogical.git", branch: "REL2_x_STABLE"

  depends_on "postgresql@17"

  def postgresql
    Formula["postgresql@17"]
  end

  def install
    ENV["PG_CONFIG"] = postgresql.opt_bin/"pg_config"
    ENV["USE_PGXS"] = "1"

    # Build using PGXS Makefile
    system "make", "clean"
    system "make", "all", "PG_CONFIG=#{ENV["PG_CONFIG"]}"

    # Install to a staging directory first
    ENV["DESTDIR"] = buildpath/"stage"
    system "make", "install", "PG_CONFIG=#{ENV["PG_CONFIG"]}"

    # Get PostgreSQL directories from pg_config
    pkglibdir = `#{ENV["PG_CONFIG"]} --pkglibdir`.chomp
    sharedir = `#{ENV["PG_CONFIG"]} --sharedir`.chomp

    # Install to Homebrew prefix (will be symlinked to PostgreSQL dirs)
    (lib/"postgresql").install Dir[buildpath/"stage#{pkglibdir}/*.dylib"]
    (share/"postgresql/extension").install Dir[buildpath/"stage#{sharedir}/extension/*"]
  end

  def post_install
    # Symlink to PostgreSQL's extension directories
    postgresql_pkglibdir = `#{postgresql.opt_bin}/pg_config --pkglibdir`.chomp
    postgresql_sharedir = `#{postgresql.opt_bin}/pg_config --sharedir`.chomp

    # Symlink .dylib files
    Dir[lib/"postgresql"/"*.dylib"].each do |dylib|
      target = Pathname.new(postgresql_pkglibdir)/File.basename(dylib)
      target.unlink if target.symlink? || target.exist?
      target.make_symlink(dylib)
    end

    # Symlink extension files
    Dir[share/"postgresql/extension"/"*"].each do |extfile|
      target = Pathname.new(postgresql_sharedir)/"extension"/File.basename(extfile)
      target.unlink if target.symlink? || target.exist?
      target.make_symlink(extfile)
    end
  end

  def caveats
    <<~EOS
      To enable pglogical, add to your postgresql.conf:

        shared_preload_libraries = 'pglogical'
        wal_level = 'logical'
        max_worker_processes = 10
        max_replication_slots = 10
        max_wal_senders = 10

      Then restart PostgreSQL:
        brew services restart postgresql@17

      And create the extension:
        psql -c "CREATE EXTENSION pglogical;"

      For bidirectional replication setup, see:
        https://github.com/willibrandon/pglogical/blob/REL2_x_STABLE/docs/bidirectional-replication.md
    EOS
  end

  test do
    # Verify PostgreSQL can find the extension
    system postgresql.opt_bin/"pg_config", "--version"
    assert_predicate lib/"postgresql"/"pglogical.dylib", :exist?
    assert_predicate share/"postgresql/extension"/"pglogical.control", :exist?
  end
end
```

#### `Formula/pglogical@16.rb` (for PostgreSQL 16)

```ruby
# typed: false
# frozen_string_literal: true

class PglogicalAT16 < Formula
  desc "PostgreSQL logical replication extension with bidirectional support"
  homepage "https://github.com/willibrandon/pglogical"
  url "https://github.com/willibrandon/pglogical/archive/refs/tags/v2.5.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "PostgreSQL"

  depends_on "postgresql@16"

  def postgresql
    Formula["postgresql@16"]
  end

  # ... same install/post_install/caveats/test as pglogical.rb
  # with postgresql@16 references
end
```

### Updated README.md

```markdown
# Homebrew Tap

This tap provides Homebrew formulae for:
- [pgtail](https://github.com/willibrandon/pgtail) - Interactive PostgreSQL log tailer
- [pglogical](https://github.com/willibrandon/pglogical) - PostgreSQL logical replication extension

## Installation

### pgtail

```bash
brew install willibrandon/tap/pgtail
```

### pglogical

```bash
# For PostgreSQL 17 (default)
brew install willibrandon/tap/pglogical

# For PostgreSQL 16
brew install willibrandon/tap/pglogical@16

# For PostgreSQL 15
brew install willibrandon/tap/pglogical@15
```

## Available Formulae

| Formula | Description | PostgreSQL Version |
|---------|-------------|-------------------|
| `pgtail` | PostgreSQL log tailer | N/A (standalone) |
| `pglogical` | Logical replication extension | 17 |
| `pglogical@16` | Logical replication extension | 16 |
| `pglogical@15` | Logical replication extension | 15 |

## Post-Installation (pglogical)

After installing pglogical, configure PostgreSQL:

```bash
# Edit postgresql.conf (location varies)
# Add these settings:
shared_preload_libraries = 'pglogical'
wal_level = 'logical'
max_worker_processes = 10
max_replication_slots = 10
max_wal_senders = 10

# Restart PostgreSQL
brew services restart postgresql@17

# Create the extension in your database
psql -d mydb -c "CREATE EXTENSION pglogical;"
```

## Troubleshooting

### pglogical: Extension not found

If PostgreSQL can't find the extension after installation:

```bash
# Reinstall to refresh symlinks
brew reinstall pglogical

# Or manually check the symlinks
ls -la $(pg_config --pkglibdir)/pglogical*
ls -la $(pg_config --sharedir)/extension/pglogical*
```

### macOS Gatekeeper Warning

If you see "cannot be opened because the developer cannot be verified":

```bash
# For pgtail
xattr -d com.apple.quarantine $(which pgtail)

# For pglogical (usually not needed as it's built from source)
xattr -d com.apple.quarantine $(pg_config --pkglibdir)/pglogical.dylib
```
```

### Directory Structure After Changes

```
homebrew-tap/
├── Formula/
│   ├── pgtail.rb           # Existing
│   ├── pglogical.rb        # New - PostgreSQL 17
│   ├── pglogical@16.rb     # New - PostgreSQL 16
│   └── pglogical@15.rb     # New - PostgreSQL 15
└── README.md               # Updated
```

### Automated Updates via GitHub Actions

The pglogical release workflow will automatically update the homebrew-tap repository when a new version is released. This requires:

1. A GitHub Personal Access Token (`HOMEBREW_TAP_TOKEN`) with `repo` scope
2. The token stored as a secret in the pglogical repository
3. The `mislav/bump-homebrew-formula-action` configured in the release workflow

The action will:
1. Calculate the SHA256 of the new release tarball
2. Update the `url` and `sha256` in each pglogical formula
3. Create a commit and push to the homebrew-tap repository

## File Changes Summary

| File | Change |
|------|--------|
| `.github/workflows/ci.yml` | New CI workflow |
| `.github/workflows/release.yml` | New release workflow |
| `wix/pglogical.wxs` | New WiX installer |
| `winget/templates/*.yaml` | New Winget manifests |
| `homebrew/pglogical.rb` | New Homebrew formula (reference copy) |
| `META.json` | New PGXN metadata |
| `CHANGELOG.md` | New changelog file |

### External Repository Changes

| Repository | File | Change |
|------------|------|--------|
| `willibrandon/homebrew-tap` | `Formula/pglogical.rb` | New formula for PG 17 |
| `willibrandon/homebrew-tap` | `Formula/pglogical@16.rb` | New formula for PG 16 |
| `willibrandon/homebrew-tap` | `Formula/pglogical@15.rb` | New formula for PG 15 |
| `willibrandon/homebrew-tap` | `README.md` | Updated with pglogical docs |

## Future Enhancements

1. **Linux packages** - deb/rpm packages via GitHub Actions
2. **Docker images** - Pre-configured PostgreSQL + pglogical images
3. **Signed releases** - GPG signing of release artifacts
4. **macOS universal binaries** - ARM64 + x86_64 fat binaries
5. **Automated changelog** - Generate from conventional commits
