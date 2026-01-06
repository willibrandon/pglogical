# Feature: GitHub Releases Distribution

**Target**: pglogical 2.5.0
**Status**: Design Proposal

## Overview

Establish automated GitHub Releases distribution for pglogical with pre-built binaries for Windows (MSI installers and ZIP archives), Linux, and macOS across PostgreSQL versions 13-18.

## Problem Statement

Currently, pglogical lacks:
1. Automated cross-platform build pipeline
2. Pre-built binary distribution for Windows users
3. MSI installers for easy Windows deployment
4. Consistent release artifacts across platforms

## Solution

Implement a GitHub Actions-based release pipeline that:
1. Builds on tag push for all supported platforms
2. Creates Windows MSI installers (one per PG version)
3. Creates platform-specific binary packages
4. Publishes all artifacts to GitHub Releases

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    GitHub Actions Release Workflow                       │
│                         (triggered on tag v*)                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     Build Matrix                                 │   │
│  │                                                                  │   │
│  │   PostgreSQL: 13, 14, 15, 16, 17, 18                            │   │
│  │   ─────────────────────────────────────────────────────────────  │   │
│  │   Windows (MSVC)  │  Linux (GCC)    │  macOS (Clang)            │   │
│  │   ─────────────────────────────────────────────────────────────  │   │
│  │   pglogical.dll   │  pglogical.so   │  pglogical.dylib          │   │
│  │   + MSI installer │  + tar.gz       │  + tar.gz                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                    │
│                                    ▼                                    │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    GitHub Release                                │   │
│  │                                                                  │   │
│  │   pglogical-2.5.0-pg17-windows-x64.msi                          │   │
│  │   pglogical-2.5.0-pg17-windows-x64.zip                          │   │
│  │   pglogical-2.5.0-pg17-linux-x64.tar.gz                         │   │
│  │   pglogical-2.5.0-pg17-macos-arm64.tar.gz                       │   │
│  │   pglogical-2.5.0-pg17-macos-x64.tar.gz                         │   │
│  │   pglogical-2.5.0-source.tar.gz                                 │   │
│  │   ... (repeat for each PG version)                              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Release Artifacts

### File Naming Convention

```
pglogical-{version}-pg{pg_version}-{platform}-{arch}.{ext}
```

Examples:
- `pglogical-2.5.0-pg17-windows-x64.msi`
- `pglogical-2.5.0-pg17-windows-x64.zip`
- `pglogical-2.5.0-pg17-linux-x64.tar.gz`
- `pglogical-2.5.0-pg17-macos-arm64.tar.gz`
- `pglogical-2.5.0-pg17-macos-x64.tar.gz`

### Complete Release Structure

```
pglogical-2.5.0/
├── Windows MSI Installers
│   ├── pglogical-2.5.0-pg18-windows-x64.msi
│   ├── pglogical-2.5.0-pg17-windows-x64.msi
│   ├── pglogical-2.5.0-pg16-windows-x64.msi
│   ├── pglogical-2.5.0-pg15-windows-x64.msi
│   ├── pglogical-2.5.0-pg14-windows-x64.msi
│   └── pglogical-2.5.0-pg13-windows-x64.msi
│
├── Windows ZIP Archives
│   ├── pglogical-2.5.0-pg18-windows-x64.zip
│   ├── pglogical-2.5.0-pg17-windows-x64.zip
│   ├── pglogical-2.5.0-pg16-windows-x64.zip
│   ├── pglogical-2.5.0-pg15-windows-x64.zip
│   ├── pglogical-2.5.0-pg14-windows-x64.zip
│   └── pglogical-2.5.0-pg13-windows-x64.zip
│
├── Linux Archives
│   ├── pglogical-2.5.0-pg18-linux-x64.tar.gz
│   ├── pglogical-2.5.0-pg17-linux-x64.tar.gz
│   ├── pglogical-2.5.0-pg16-linux-x64.tar.gz
│   ├── pglogical-2.5.0-pg15-linux-x64.tar.gz
│   ├── pglogical-2.5.0-pg14-linux-x64.tar.gz
│   └── pglogical-2.5.0-pg13-linux-x64.tar.gz
│
├── macOS Archives (Apple Silicon)
│   ├── pglogical-2.5.0-pg18-macos-arm64.tar.gz
│   ├── pglogical-2.5.0-pg17-macos-arm64.tar.gz
│   ├── pglogical-2.5.0-pg16-macos-arm64.tar.gz
│   ├── pglogical-2.5.0-pg15-macos-arm64.tar.gz
│   ├── pglogical-2.5.0-pg14-macos-arm64.tar.gz
│   └── pglogical-2.5.0-pg13-macos-arm64.tar.gz
│
├── macOS Archives (Intel)
│   ├── pglogical-2.5.0-pg18-macos-x64.tar.gz
│   ├── pglogical-2.5.0-pg17-macos-x64.tar.gz
│   ├── pglogical-2.5.0-pg16-macos-x64.tar.gz
│   ├── pglogical-2.5.0-pg15-macos-x64.tar.gz
│   ├── pglogical-2.5.0-pg14-macos-x64.tar.gz
│   └── pglogical-2.5.0-pg13-macos-x64.tar.gz
│
└── Source Archives
    ├── pglogical-2.5.0-source.tar.gz
    └── pglogical-2.5.0-source.zip
```

### Package Contents

#### Windows ZIP/MSI Contents
```
pglogical-2.5.0-pg17-windows-x64/
├── lib/
│   ├── pglogical.dll
│   └── pglogical_output.dll
├── share/
│   └── extension/
│       ├── pglogical.control
│       ├── pglogical--2.5.0.sql
│       └── pglogical--2.4.6--2.5.0.sql
└── README.txt
```

#### Linux/macOS tar.gz Contents
```
pglogical-2.5.0-pg17-linux-x64/
├── lib/
│   ├── pglogical.so          (or .dylib on macOS)
│   └── pglogical_output.so
├── share/
│   └── extension/
│       ├── pglogical.control
│       ├── pglogical--2.5.0.sql
│       └── pglogical--2.4.6--2.5.0.sql
├── README.md
└── install.sh                 (helper script)
```

## Implementation

### Directory Structure

```
pglogical/
├── .github/
│   └── workflows/
│       ├── ci.yml              # CI on push/PR
│       └── release.yml         # Release pipeline
├── wix/
│   └── pglogical.wxs           # WiX installer definition
├── packaging/
│   ├── install.sh              # Linux/macOS install helper
│   └── README.txt              # Windows package readme
└── ...
```

### GitHub Actions Workflow

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

      - uses: actions/checkout@v6
        with:
          submodules: recursive

      - name: Install PostgreSQL ${{ matrix.pg_version }}
        run: |
          sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
          wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
          sudo apt-get update
          sudo apt-get install -y postgresql-${{ matrix.pg_version }} \
            postgresql-server-dev-${{ matrix.pg_version }}

      - name: Build pglogical
        run: |
          export PATH="/usr/lib/postgresql/${{ matrix.pg_version }}/bin:$PATH"
          make clean all

      - name: Install pglogical
        run: |
          export PATH="/usr/lib/postgresql/${{ matrix.pg_version }}/bin:$PATH"
          sudo make install

      - name: Run regression tests
        run: |
          export PATH="/usr/lib/postgresql/${{ matrix.pg_version }}/bin:$PATH"
          make check

  build-windows:
    runs-on: windows-latest
    strategy:
      fail-fast: false
      matrix:
        pg_version: [13, 14, 15, 16, 17, 18]
    steps:
      - name: Configure git for HTTPS submodules
        run: git config --global url."https://github.com/".insteadOf "git@github.com:"

      - uses: actions/checkout@v6
        with:
          submodules: recursive

      - name: Install PostgreSQL ${{ matrix.pg_version }}
        run: |
          choco install postgresql${{ matrix.pg_version }} --params '/Password:postgres' -y
          echo "C:\Program Files\PostgreSQL\${{ matrix.pg_version }}\bin" | Out-File -Append $env:GITHUB_PATH

      - name: Setup MSVC
        uses: ilammy/msvc-dev-cmd@v1

      - name: Configure CMake
        run: |
          cmake -B build -S . -G "Visual Studio 17 2022" -A x64 `
            -DCMAKE_BUILD_TYPE=Release `
            -DPostgreSQL_ROOT="C:\Program Files\PostgreSQL\${{ matrix.pg_version }}"

      - name: Build
        run: cmake --build build --config Release

      - name: Upload build artifacts
        uses: actions/upload-artifact@v6
        with:
          name: pglogical-pg${{ matrix.pg_version }}-windows-ci
          path: |
            build/Release/*.dll
            *.sql
            *.control

  build-macos:
    runs-on: macos-14  # ARM64 runner
    strategy:
      fail-fast: false
      matrix:
        pg_version: [13, 14, 15, 16, 17, 18]
    steps:
      - name: Configure git for HTTPS submodules
        run: git config --global url."https://github.com/".insteadOf "git@github.com:"

      - uses: actions/checkout@v6
        with:
          submodules: recursive

      - name: Install PostgreSQL ${{ matrix.pg_version }}
        run: |
          brew install postgresql@${{ matrix.pg_version }}
          echo "$(brew --prefix postgresql@${{ matrix.pg_version }})/bin" >> $GITHUB_PATH

      - name: Build pglogical
        run: |
          export PATH="$(brew --prefix postgresql@${{ matrix.pg_version }})/bin:$PATH"
          make clean all

      - name: Run regression tests
        run: |
          export PATH="$(brew --prefix postgresql@${{ matrix.pg_version }})/bin:$PATH"
          make check
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
  # ============================================================
  # Windows Builds
  # ============================================================
  build-windows:
    runs-on: windows-latest
    strategy:
      fail-fast: false
      matrix:
        pg_version: [13, 14, 15, 16, 17, 18]
    steps:
      - name: Configure git for HTTPS submodules
        run: git config --global url."https://github.com/".insteadOf "git@github.com:"

      - uses: actions/checkout@v6
        with:
          submodules: recursive

      - name: Install PostgreSQL ${{ matrix.pg_version }}
        run: |
          choco install postgresql${{ matrix.pg_version }} --params '/Password:postgres' -y

      - name: Setup MSVC
        uses: ilammy/msvc-dev-cmd@v1

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

          # Create directory structure
          New-Item -ItemType Directory -Force -Path "package/lib"
          New-Item -ItemType Directory -Force -Path "package/share/extension"

          # Copy DLLs
          Copy-Item "build/Release/pglogical.dll" "package/lib/"
          Copy-Item "build/Release/pglogical_output.dll" "package/lib/"

          # Copy SQL and control files
          Copy-Item "*.control" "package/share/extension/"
          Copy-Item "pglogical--*.sql" "package/share/extension/"

          # Copy README
          Copy-Item "packaging/README.txt" "package/" -ErrorAction SilentlyContinue

          # Create README if not exists
          if (-not (Test-Path "package/README.txt")) {
            @"
          pglogical $VERSION for PostgreSQL $PG_VER
          ==========================================

          Installation:
          1. Copy lib/*.dll to your PostgreSQL lib directory
          2. Copy share/extension/* to your PostgreSQL share/extension directory
          3. Restart PostgreSQL
          4. Run: CREATE EXTENSION pglogical;

          For documentation, see: https://github.com/willibrandon/pglogical
          "@ | Out-File -FilePath "package/README.txt" -Encoding UTF8
          }

      - name: Create ZIP archive
        run: |
          $VERSION = "${{ env.VERSION }}".TrimStart('v')
          Compress-Archive -Path "package/*" `
            -DestinationPath "pglogical-$VERSION-pg${{ matrix.pg_version }}-windows-x64.zip"

      - name: Install WiX Toolset
        run: dotnet tool install --global wix

      - name: Build MSI installer
        run: |
          $VERSION = "${{ env.VERSION }}".TrimStart('v')

          # Create wix directory if needed
          if (-not (Test-Path "wix")) {
            New-Item -ItemType Directory -Force -Path "wix"
          }

          wix build wix/pglogical.wxs `
            -d Version=$VERSION `
            -d PgVersion=${{ matrix.pg_version }} `
            -d SourceDir=package `
            -o "pglogical-$VERSION-pg${{ matrix.pg_version }}-windows-x64.msi"

      - name: Upload Windows artifacts
        uses: actions/upload-artifact@v6
        with:
          name: windows-pg${{ matrix.pg_version }}
          path: |
            *.zip
            *.msi

  # ============================================================
  # Linux Builds
  # ============================================================
  build-linux:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        pg_version: [13, 14, 15, 16, 17, 18]
    steps:
      - name: Configure git for HTTPS submodules
        run: git config --global url."https://github.com/".insteadOf "git@github.com:"

      - uses: actions/checkout@v6
        with:
          submodules: recursive

      - name: Install PostgreSQL ${{ matrix.pg_version }}
        run: |
          sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
          wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
          sudo apt-get update
          sudo apt-get install -y postgresql-${{ matrix.pg_version }} \
            postgresql-server-dev-${{ matrix.pg_version }}

      - name: Build pglogical
        run: |
          export PATH="/usr/lib/postgresql/${{ matrix.pg_version }}/bin:$PATH"
          make clean all

      - name: Prepare package directory
        run: |
          VERSION="${{ env.VERSION }}"
          VERSION="${VERSION#v}"
          PG_VER="${{ matrix.pg_version }}"
          PKG_NAME="pglogical-$VERSION-pg$PG_VER-linux-x64"

          mkdir -p "$PKG_NAME/lib"
          mkdir -p "$PKG_NAME/share/extension"

          # Copy shared libraries
          cp pglogical.so "$PKG_NAME/lib/" 2>/dev/null || true
          cp pglogical_output.so "$PKG_NAME/lib/" 2>/dev/null || true

          # Copy SQL and control files
          cp *.control "$PKG_NAME/share/extension/"
          cp pglogical--*.sql "$PKG_NAME/share/extension/"

          # Copy install script
          cp packaging/install.sh "$PKG_NAME/" 2>/dev/null || true

          # Create install script if not exists
          if [ ! -f "$PKG_NAME/install.sh" ]; then
            cat > "$PKG_NAME/install.sh" << 'SCRIPT'
          #!/bin/bash
          set -e

          # pglogical installation script

          PG_CONFIG="${PG_CONFIG:-pg_config}"

          if ! command -v "$PG_CONFIG" &> /dev/null; then
              echo "Error: pg_config not found. Set PG_CONFIG environment variable."
              exit 1
          fi

          PKGLIBDIR=$("$PG_CONFIG" --pkglibdir)
          SHAREDIR=$("$PG_CONFIG" --sharedir)

          echo "Installing pglogical to PostgreSQL at:"
          echo "  lib:       $PKGLIBDIR"
          echo "  extension: $SHAREDIR/extension"
          echo ""

          # Install libraries
          sudo cp lib/*.so "$PKGLIBDIR/"

          # Install extension files
          sudo cp share/extension/* "$SHAREDIR/extension/"

          echo "Installation complete!"
          echo ""
          echo "Next steps:"
          echo "1. Add to postgresql.conf:"
          echo "   shared_preload_libraries = 'pglogical'"
          echo "   wal_level = 'logical'"
          echo ""
          echo "2. Restart PostgreSQL"
          echo ""
          echo "3. Create extension:"
          echo "   CREATE EXTENSION pglogical;"
          SCRIPT
            chmod +x "$PKG_NAME/install.sh"
          fi

          # Create README
          cat > "$PKG_NAME/README.md" << EOF
          # pglogical $VERSION for PostgreSQL $PG_VER (Linux x64)

          ## Quick Installation

          \`\`\`bash
          ./install.sh
          \`\`\`

          ## Manual Installation

          \`\`\`bash
          # Find PostgreSQL directories
          PKGLIBDIR=\$(pg_config --pkglibdir)
          SHAREDIR=\$(pg_config --sharedir)

          # Copy files
          sudo cp lib/*.so "\$PKGLIBDIR/"
          sudo cp share/extension/* "\$SHAREDIR/extension/"
          \`\`\`

          ## Configuration

          Add to \`postgresql.conf\`:
          \`\`\`
          shared_preload_libraries = 'pglogical'
          wal_level = 'logical'
          max_worker_processes = 10
          max_replication_slots = 10
          max_wal_senders = 10
          \`\`\`

          Then restart PostgreSQL and run:
          \`\`\`sql
          CREATE EXTENSION pglogical;
          \`\`\`

          ## Documentation

          https://github.com/willibrandon/pglogical
          EOF

          # Create tarball
          tar czf "$PKG_NAME.tar.gz" "$PKG_NAME"

      - name: Upload Linux artifacts
        uses: actions/upload-artifact@v6
        with:
          name: linux-pg${{ matrix.pg_version }}
          path: "*.tar.gz"

  # ============================================================
  # macOS Builds (ARM64 - Apple Silicon)
  # ============================================================
  build-macos-arm64:
    runs-on: macos-14
    strategy:
      fail-fast: false
      matrix:
        pg_version: [13, 14, 15, 16, 17, 18]
    steps:
      - name: Configure git for HTTPS submodules
        run: git config --global url."https://github.com/".insteadOf "git@github.com:"

      - uses: actions/checkout@v6
        with:
          submodules: recursive

      - name: Install PostgreSQL ${{ matrix.pg_version }}
        run: |
          brew install postgresql@${{ matrix.pg_version }}

      - name: Build pglogical
        run: |
          export PATH="$(brew --prefix postgresql@${{ matrix.pg_version }})/bin:$PATH"
          make clean all

      - name: Prepare package directory
        run: |
          VERSION="${{ env.VERSION }}"
          VERSION="${VERSION#v}"
          PG_VER="${{ matrix.pg_version }}"
          PKG_NAME="pglogical-$VERSION-pg$PG_VER-macos-arm64"

          mkdir -p "$PKG_NAME/lib"
          mkdir -p "$PKG_NAME/share/extension"

          # Copy shared libraries
          cp *.dylib "$PKG_NAME/lib/" 2>/dev/null || true

          # Copy SQL and control files
          cp *.control "$PKG_NAME/share/extension/"
          cp pglogical--*.sql "$PKG_NAME/share/extension/"

          # Create install script
          cat > "$PKG_NAME/install.sh" << 'SCRIPT'
          #!/bin/bash
          set -e

          PG_CONFIG="${PG_CONFIG:-pg_config}"

          if ! command -v "$PG_CONFIG" &> /dev/null; then
              echo "Error: pg_config not found. Set PG_CONFIG environment variable."
              exit 1
          fi

          PKGLIBDIR=$("$PG_CONFIG" --pkglibdir)
          SHAREDIR=$("$PG_CONFIG" --sharedir)

          echo "Installing pglogical..."
          cp lib/*.dylib "$PKGLIBDIR/"
          cp share/extension/* "$SHAREDIR/extension/"
          echo "Done! Restart PostgreSQL and run: CREATE EXTENSION pglogical;"
          SCRIPT
          chmod +x "$PKG_NAME/install.sh"

          # Create README
          cat > "$PKG_NAME/README.md" << EOF
          # pglogical $VERSION for PostgreSQL $PG_VER (macOS ARM64)

          ## Installation

          \`\`\`bash
          ./install.sh
          \`\`\`

          See https://github.com/willibrandon/pglogical for documentation.
          EOF

          tar czf "$PKG_NAME.tar.gz" "$PKG_NAME"

      - name: Upload macOS ARM64 artifacts
        uses: actions/upload-artifact@v6
        with:
          name: macos-arm64-pg${{ matrix.pg_version }}
          path: "*.tar.gz"

  # ============================================================
  # macOS Builds (x64 - Intel)
  # ============================================================
  build-macos-x64:
    runs-on: macos-13
    strategy:
      fail-fast: false
      matrix:
        pg_version: [13, 14, 15, 16, 17, 18]
    steps:
      - name: Configure git for HTTPS submodules
        run: git config --global url."https://github.com/".insteadOf "git@github.com:"

      - uses: actions/checkout@v6
        with:
          submodules: recursive

      - name: Install PostgreSQL ${{ matrix.pg_version }}
        run: |
          brew install postgresql@${{ matrix.pg_version }}

      - name: Build pglogical
        run: |
          export PATH="$(brew --prefix postgresql@${{ matrix.pg_version }})/bin:$PATH"
          make clean all

      - name: Prepare package directory
        run: |
          VERSION="${{ env.VERSION }}"
          VERSION="${VERSION#v}"
          PG_VER="${{ matrix.pg_version }}"
          PKG_NAME="pglogical-$VERSION-pg$PG_VER-macos-x64"

          mkdir -p "$PKG_NAME/lib"
          mkdir -p "$PKG_NAME/share/extension"

          cp *.dylib "$PKG_NAME/lib/" 2>/dev/null || true
          cp *.control "$PKG_NAME/share/extension/"
          cp pglogical--*.sql "$PKG_NAME/share/extension/"

          cat > "$PKG_NAME/install.sh" << 'SCRIPT'
          #!/bin/bash
          set -e
          PG_CONFIG="${PG_CONFIG:-pg_config}"
          PKGLIBDIR=$("$PG_CONFIG" --pkglibdir)
          SHAREDIR=$("$PG_CONFIG" --sharedir)
          cp lib/*.dylib "$PKGLIBDIR/"
          cp share/extension/* "$SHAREDIR/extension/"
          echo "Done! Restart PostgreSQL and run: CREATE EXTENSION pglogical;"
          SCRIPT
          chmod +x "$PKG_NAME/install.sh"

          cat > "$PKG_NAME/README.md" << EOF
          # pglogical $VERSION for PostgreSQL $PG_VER (macOS x64)
          Run ./install.sh to install. See https://github.com/willibrandon/pglogical
          EOF

          tar czf "$PKG_NAME.tar.gz" "$PKG_NAME"

      - name: Upload macOS x64 artifacts
        uses: actions/upload-artifact@v6
        with:
          name: macos-x64-pg${{ matrix.pg_version }}
          path: "*.tar.gz"

  # ============================================================
  # Source Package
  # ============================================================
  build-source:
    runs-on: ubuntu-latest
    steps:
      - name: Configure git for HTTPS submodules
        run: git config --global url."https://github.com/".insteadOf "git@github.com:"

      - uses: actions/checkout@v6
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
        uses: actions/upload-artifact@v6
        with:
          name: source-packages
          path: |
            *.tar.gz
            *.zip

  # ============================================================
  # Create GitHub Release
  # ============================================================
  create-release:
    needs: [build-windows, build-linux, build-macos-arm64, build-macos-x64, build-source]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Download all artifacts
        uses: actions/download-artifact@v6
        with:
          path: artifacts

      - name: Organize artifacts
        run: |
          mkdir -p release
          find artifacts -type f \( -name "*.zip" -o -name "*.msi" -o -name "*.tar.gz" \) -exec cp {} release/ \;
          ls -la release/

      - name: Generate release notes
        id: release_notes
        run: |
          VERSION="${{ env.VERSION }}"
          VERSION="${VERSION#v}"

          cat > release_notes.md << 'EOF'
          ## Installation

          ### Windows (MSI Installer - Recommended)

          1. Download the MSI for your PostgreSQL version
          2. Run the installer
          3. The installer will detect your PostgreSQL installation and install the extension files
          4. Restart PostgreSQL and run: `CREATE EXTENSION pglogical;`

          ### Windows (ZIP Archive)

          1. Download the ZIP for your PostgreSQL version
          2. Extract to a temporary location
          3. Copy `lib/*.dll` to your PostgreSQL `lib` directory
          4. Copy `share/extension/*` to your PostgreSQL `share/extension` directory
          5. Restart PostgreSQL and run: `CREATE EXTENSION pglogical;`

          ### Linux

          1. Download the tar.gz for your PostgreSQL version
          2. Extract: `tar xzf pglogical-*.tar.gz`
          3. Run: `./install.sh` (or manually copy files)
          4. Configure postgresql.conf (see below)
          5. Restart PostgreSQL and run: `CREATE EXTENSION pglogical;`

          ### macOS

          1. Download the tar.gz for your PostgreSQL version and architecture (arm64 or x64)
          2. Extract: `tar xzf pglogical-*.tar.gz`
          3. Run: `./install.sh`
          4. Configure postgresql.conf (see below)
          5. Restart PostgreSQL and run: `CREATE EXTENSION pglogical;`

          ### From Source

          ```bash
          tar xzf pglogical-*-source.tar.gz
          cd pglogical-*
          make && sudo make install
          ```

          ## Required Configuration

          Add to `postgresql.conf`:

          ```ini
          shared_preload_libraries = 'pglogical'
          wal_level = 'logical'
          max_worker_processes = 10
          max_replication_slots = 10
          max_wal_senders = 10
          ```

          ## Supported PostgreSQL Versions

          | PostgreSQL | Windows | Linux | macOS ARM64 | macOS x64 |
          |------------|---------|-------|-------------|-----------|
          | 18         | ✅      | ✅    | ✅          | ✅        |
          | 17         | ✅      | ✅    | ✅          | ✅        |
          | 16         | ✅      | ✅    | ✅          | ✅        |
          | 15         | ✅      | ✅    | ✅          | ✅        |
          | 14         | ✅      | ✅    | ✅          | ✅        |
          | 13         | ✅      | ✅    | ✅          | ✅        |

          ## Checksums

          See `checksums.txt` artifact for SHA256 checksums of all files.

          ## Documentation

          - [README](https://github.com/willibrandon/pglogical/blob/REL2_x_STABLE/README.md)
          - [Bidirectional Replication Guide](https://github.com/willibrandon/pglogical/blob/REL2_x_STABLE/docs/bidirectional-replication.md)

          EOF

      - name: Generate checksums
        run: |
          cd release
          sha256sum * > checksums.txt
          cat checksums.txt

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          name: pglogical ${{ env.VERSION }}
          body_path: release_notes.md
          files: |
            release/*
          draft: false
          prerelease: ${{ contains(env.VERSION, '-') }}
```

### WiX Installer Definition

#### `wix/pglogical.wxs`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!--
  pglogical Windows Installer (WiX v5)

  Build parameters (passed via -d):
    Version     - e.g., 2.5.0
    PgVersion   - e.g., 17
    SourceDir   - Path to package directory containing lib/ and share/

  Build command:
    wix build pglogical.wxs -d Version=2.5.0 -d PgVersion=17 -d SourceDir=package -o pglogical.msi
-->
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs"
     xmlns:ui="http://wixtoolset.org/schemas/v4/wxs/ui">

  <?define ProductName = "pglogical for PostgreSQL $(var.PgVersion)" ?>
  <?define Manufacturer = "willibrandon" ?>

  <!-- Generate unique UpgradeCode per PG version to allow side-by-side -->
  <!-- Using a deterministic GUID pattern based on PG version -->
  <?if $(var.PgVersion) = 13 ?>
    <?define UpgradeCode = "A1B2C3D4-E5F6-7890-1301-000000000001" ?>
  <?elseif $(var.PgVersion) = 14 ?>
    <?define UpgradeCode = "A1B2C3D4-E5F6-7890-1401-000000000001" ?>
  <?elseif $(var.PgVersion) = 15 ?>
    <?define UpgradeCode = "A1B2C3D4-E5F6-7890-1501-000000000001" ?>
  <?elseif $(var.PgVersion) = 16 ?>
    <?define UpgradeCode = "A1B2C3D4-E5F6-7890-1601-000000000001" ?>
  <?elseif $(var.PgVersion) = 17 ?>
    <?define UpgradeCode = "A1B2C3D4-E5F6-7890-1701-000000000001" ?>
  <?elseif $(var.PgVersion) = 18 ?>
    <?define UpgradeCode = "A1B2C3D4-E5F6-7890-1801-000000000001" ?>
  <?endif ?>

  <Package Name="$(var.ProductName)"
           Version="$(var.Version).0"
           Manufacturer="$(var.Manufacturer)"
           UpgradeCode="$(var.UpgradeCode)"
           Scope="perMachine"
           Compressed="yes">

    <SummaryInformation Description="PostgreSQL Logical Replication Extension for PostgreSQL $(var.PgVersion)"
                        Manufacturer="$(var.Manufacturer)" />

    <!-- Allow upgrades, prevent downgrades -->
    <MajorUpgrade DowngradeErrorMessage="A newer version of $(var.ProductName) is already installed."
                  AllowSameVersionUpgrades="yes" />

    <!-- Embed files in MSI -->
    <MediaTemplate EmbedCab="yes" CompressionLevel="high" />

    <!-- ============================================================ -->
    <!-- Properties -->
    <!-- ============================================================ -->

    <!-- Try to find PostgreSQL installation from registry -->
    <Property Id="PGINSTALLDIR" Secure="yes">
      <RegistrySearch Id="PgInstallDirSearch"
                      Root="HKLM"
                      Key="SOFTWARE\PostgreSQL\Installations\postgresql-x64-$(var.PgVersion)"
                      Name="Base Directory"
                      Type="directory" />
    </Property>

    <!-- Alternative registry location -->
    <Property Id="PGINSTALLDIR2" Secure="yes">
      <RegistrySearch Id="PgInstallDirSearch2"
                      Root="HKLM"
                      Key="SOFTWARE\PostgreSQL\Installations\postgresql-$(var.PgVersion)"
                      Name="Base Directory"
                      Type="directory" />
    </Property>

    <!-- Fallback to common installation path -->
    <SetProperty Id="PGINSTALLDIR"
                 Value="[PGINSTALLDIR2]"
                 Before="CostFinalize"
                 Condition="NOT PGINSTALLDIR AND PGINSTALLDIR2" />

    <SetProperty Id="PGINSTALLDIR"
                 Value="[ProgramFiles64Folder]PostgreSQL\$(var.PgVersion)"
                 Before="CostFinalize"
                 Condition="NOT PGINSTALLDIR" />

    <!-- ============================================================ -->
    <!-- UI Configuration -->
    <!-- ============================================================ -->

    <ui:WixUI Id="WixUI_InstallDir" InstallDirectory="PGINSTALLDIR" />

    <!-- License -->
    <WixVariable Id="WixUILicenseRtf" Value="wix\license.rtf" />

    <!-- ============================================================ -->
    <!-- Directory Structure -->
    <!-- ============================================================ -->

    <StandardDirectory Id="ProgramFiles64Folder">
      <Directory Id="PGINSTALLDIR" Name="PostgreSQL">
        <Directory Id="LIBDIR" Name="lib" />
        <Directory Id="SHAREDIR" Name="share">
          <Directory Id="EXTENSIONDIR" Name="extension" />
        </Directory>
      </Directory>
    </StandardDirectory>

    <!-- ============================================================ -->
    <!-- Components -->
    <!-- ============================================================ -->

    <!-- DLL Components -->
    <ComponentGroup Id="DllComponents" Directory="LIBDIR">
      <Component Id="pglogical_dll" Guid="B2C3D4E5-F6A7-8901-$(var.PgVersion)01-111111111111">
        <File Id="pglogical_dll_file"
              Source="$(var.SourceDir)\lib\pglogical.dll"
              KeyPath="yes" />
      </Component>
      <Component Id="pglogical_output_dll" Guid="C3D4E5F6-A7B8-9012-$(var.PgVersion)01-222222222222">
        <File Id="pglogical_output_dll_file"
              Source="$(var.SourceDir)\lib\pglogical_output.dll"
              KeyPath="yes" />
      </Component>
    </ComponentGroup>

    <!-- Extension Files Components -->
    <ComponentGroup Id="ExtensionComponents" Directory="EXTENSIONDIR">
      <Component Id="control_file" Guid="D4E5F6A7-B890-1234-$(var.PgVersion)01-333333333333">
        <File Id="pglogical_control"
              Source="$(var.SourceDir)\share\extension\pglogical.control"
              KeyPath="yes" />
      </Component>
      <Component Id="sql_files" Guid="E5F6A7B8-9012-3456-$(var.PgVersion)01-444444444444">
        <File Id="pglogical_sql_base"
              Source="$(var.SourceDir)\share\extension\pglogical--$(var.Version).sql" />
        <!-- Include upgrade scripts if present -->
        <File Id="pglogical_sql_upgrade"
              Source="$(var.SourceDir)\share\extension\pglogical--*.sql"
              Condition="false" /><!-- Placeholder for upgrade scripts -->
      </Component>
    </ComponentGroup>

    <!-- ============================================================ -->
    <!-- Features -->
    <!-- ============================================================ -->

    <Feature Id="MainFeature"
             Title="pglogical Extension"
             Description="PostgreSQL logical replication extension files"
             Level="1"
             AllowAbsent="no">
      <ComponentGroupRef Id="DllComponents" />
      <ComponentGroupRef Id="ExtensionComponents" />
    </Feature>

    <!-- ============================================================ -->
    <!-- Custom Actions -->
    <!-- ============================================================ -->

    <!-- Validate PostgreSQL installation exists -->
    <Property Id="PGINSTALLVALID" Value="0" />

    <CustomAction Id="ValidatePgInstall"
                  Script="vbscript"
                  Execute="immediate"
                  Return="check">
      <![CDATA[
        Dim fso, pgDir
        Set fso = CreateObject("Scripting.FileSystemObject")
        pgDir = Session.Property("PGINSTALLDIR")

        If fso.FolderExists(pgDir) Then
          If fso.FolderExists(pgDir & "\lib") And fso.FolderExists(pgDir & "\share\extension") Then
            Session.Property("PGINSTALLVALID") = "1"
          End If
        End If
      ]]>
    </CustomAction>

    <InstallUISequence>
      <Custom Action="ValidatePgInstall" After="CostFinalize" />
    </InstallUISequence>

  </Package>
</Wix>
```

#### `wix/license.rtf`

```rtf
{\rtf1\ansi\deff0
{\fonttbl{\f0\fnil\fcharset0 Arial;}}
\viewkind4\uc1\pard\lang1033\f0\fs20

\b pglogical - PostgreSQL Logical Replication\b0\par
\par
Copyright (c) 2015-2025, PostgreSQL Global Development Group\par
\par
Permission to use, copy, modify, and distribute this software and its documentation for any purpose, without fee, and without a written agreement is hereby granted, provided that the above copyright notice and this paragraph and the following two paragraphs appear in all copies.\par
\par
IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE UNIVERSITY OF CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.\par
\par
THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE SOFTWARE PROVIDED HEREUNDER IS ON AN "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATIONS TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.\par
}
```

### Helper Scripts

#### `packaging/install.sh`

```bash
#!/bin/bash
#
# pglogical installation script for Linux/macOS
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PG_CONFIG="${PG_CONFIG:-pg_config}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "pglogical Installer"
echo "==================="
echo ""

# Check for pg_config
if ! command -v "$PG_CONFIG" &> /dev/null; then
    echo -e "${RED}Error: pg_config not found${NC}"
    echo ""
    echo "Please ensure PostgreSQL is installed and pg_config is in your PATH,"
    echo "or set the PG_CONFIG environment variable:"
    echo ""
    echo "  export PG_CONFIG=/path/to/pg_config"
    echo "  ./install.sh"
    exit 1
fi

# Get PostgreSQL directories
PKGLIBDIR=$("$PG_CONFIG" --pkglibdir)
SHAREDIR=$("$PG_CONFIG" --sharedir)
PG_VERSION=$("$PG_CONFIG" --version | grep -oE '[0-9]+' | head -1)

echo "PostgreSQL version: $PG_VERSION"
echo "Library directory:  $PKGLIBDIR"
echo "Share directory:    $SHAREDIR/extension"
echo ""

# Check if directories exist
if [ ! -d "$PKGLIBDIR" ]; then
    echo -e "${RED}Error: Library directory does not exist: $PKGLIBDIR${NC}"
    exit 1
fi

if [ ! -d "$SHAREDIR/extension" ]; then
    echo -e "${RED}Error: Extension directory does not exist: $SHAREDIR/extension${NC}"
    exit 1
fi

# Check for sudo requirement
NEED_SUDO=""
if [ ! -w "$PKGLIBDIR" ]; then
    NEED_SUDO="sudo"
    echo -e "${YELLOW}Note: Installation requires sudo privileges${NC}"
    echo ""
fi

# Install libraries
echo "Installing shared libraries..."
if [ -d "$SCRIPT_DIR/lib" ]; then
    $NEED_SUDO cp "$SCRIPT_DIR"/lib/*.so "$PKGLIBDIR/" 2>/dev/null || \
    $NEED_SUDO cp "$SCRIPT_DIR"/lib/*.dylib "$PKGLIBDIR/" 2>/dev/null || \
    true
fi

# Install extension files
echo "Installing extension files..."
if [ -d "$SCRIPT_DIR/share/extension" ]; then
    $NEED_SUDO cp "$SCRIPT_DIR"/share/extension/* "$SHAREDIR/extension/"
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Add to postgresql.conf:"
echo "   shared_preload_libraries = 'pglogical'"
echo "   wal_level = 'logical'"
echo "   max_worker_processes = 10"
echo "   max_replication_slots = 10"
echo "   max_wal_senders = 10"
echo ""
echo "2. Restart PostgreSQL"
echo ""
echo "3. Create the extension in your database:"
echo "   CREATE EXTENSION pglogical;"
echo ""
echo "For documentation, see: https://github.com/willibrandon/pglogical"
```

#### `packaging/README.txt` (Windows)

```text
pglogical - PostgreSQL Logical Replication Extension
=====================================================

Installation (Manual)
---------------------

1. Copy the contents of lib\ to your PostgreSQL lib directory:
   - Default: C:\Program Files\PostgreSQL\{version}\lib\

2. Copy the contents of share\extension\ to your PostgreSQL extension directory:
   - Default: C:\Program Files\PostgreSQL\{version}\share\extension\

3. Edit postgresql.conf and add:
   shared_preload_libraries = 'pglogical'
   wal_level = 'logical'
   max_worker_processes = 10
   max_replication_slots = 10
   max_wal_senders = 10

4. Restart PostgreSQL service

5. Connect to your database and run:
   CREATE EXTENSION pglogical;


Documentation
-------------

https://github.com/willibrandon/pglogical


Support
-------

https://github.com/willibrandon/pglogical/issues
```

## Release Process

### Pre-release Checklist

1. Update version in:
   - [ ] `pglogical.control`
   - [ ] `CMakeLists.txt`
   - [ ] `Makefile` (if version is hardcoded)

2. Create/update upgrade SQL script:
   - [ ] `pglogical--{old_version}--{new_version}.sql`

3. Update documentation:
   - [ ] `CHANGELOG.md`
   - [ ] `README.md` (if needed)

4. Verify submodule setup:
   - [ ] `.gitmodules` uses HTTPS URL (not SSH)
   - [ ] Submodule is at correct commit (`git submodule status`)

5. Test builds locally:
   - [ ] Windows build succeeds
   - [ ] Linux build succeeds
   - [ ] macOS build succeeds

6. Ensure CI passes on all platforms

### Creating a Release

```bash
# Ensure you're on the release branch
git checkout REL2_x_STABLE

# Create annotated tag
git tag -a v2.5.0 -m "Release 2.5.0"

# Push tag to trigger release workflow
git push origin v2.5.0
```

### Post-release Verification

1. [ ] GitHub Release created with all artifacts
2. [ ] Download and verify checksums
3. [ ] Test MSI installation on Windows
4. [ ] Test tar.gz installation on Linux
5. [ ] Test tar.gz installation on macOS

## Configuration

### Repository Settings

1. Enable GitHub Actions in repository settings
2. Configure branch protection for `REL2_x_STABLE`

### Required Permissions

The release workflow requires `contents: write` permission to create releases. This is configured in the workflow file.

## Troubleshooting

### Build Failures

**Windows: PostgreSQL not found**
- Ensure chocolatey package installed correctly
- Check that PostgreSQL registry keys exist

**Linux: Missing development headers**
- Install `postgresql-server-dev-{version}` package

**macOS: Homebrew PostgreSQL not found**
- Run `brew link postgresql@{version}` if needed

### MSI Installation Issues

**"PostgreSQL installation not found"**
- Manually select the PostgreSQL installation directory during install
- Verify PostgreSQL is installed (check Program Files)

**Permission denied**
- Run installer as Administrator
- Check that PostgreSQL service is stopped

### Extension Not Loading

**"could not load library pglogical"**
- Verify DLL/SO is in correct directory
- Check PostgreSQL log for detailed error
- On Windows, ensure Visual C++ Redistributable is installed

## Future Enhancements

1. **Code signing** - Sign Windows binaries and MSI
2. **Notarization** - Notarize macOS binaries for Gatekeeper
3. **ARM64 Windows** - Add Windows ARM64 builds when PostgreSQL supports it
4. **Automated testing** - Run installation tests in CI
5. **Delta updates** - Support incremental MSI updates
