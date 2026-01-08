# CI/CD Documentation for pglogical

This document describes the GitHub Actions CI/CD infrastructure for building and releasing pglogical.

## Workflows

### CI Workflow (`.github/workflows/ci.yml`)

Runs on:
- Push to `REL2_x_STABLE` branch
- Push to `windows-build` branch
- Pull requests targeting `REL2_x_STABLE`

**Build Matrix**:
| Platform | PostgreSQL Versions | Architecture |
|----------|---------------------|--------------|
| ubuntu-latest | 13, 14, 15, 16, 17, 18 | x64 |
| windows-2022 | 13, 14, 15, 16, 17, 18 | x64 |
| macos-13 | 13, 14, 15, 16, 17, 18 | x64 (Intel) |
| macos-14 | 14, 15, 16, 17, 18 | arm64 (Apple Silicon) |

Note: macOS ARM64 (macos-14) excludes PostgreSQL 13 as Homebrew may not provide it for that architecture.

**Build Steps**:
1. Checkout repository with submodules
2. Install PostgreSQL development files (platform-specific)
3. Build extension (make on Linux/macOS, CMake on Windows)
4. Run regression tests on all platforms
5. Upload test artifacts on failure

### Release Workflow (`.github/workflows/release.yml`)

Runs on:
- Push of tags matching `v*` pattern (e.g., `v2.5.0`, `v2.5.0-beta1`)

**Outputs**:
- Binary packages for all platforms
- Source archives (tar.gz and zip)
- SHA256 checksums file
- GitHub Release with attached assets

## Branch Protection

To enforce CI validation before merging, configure branch protection for `REL2_x_STABLE`:

1. Go to Repository Settings → Branches
2. Add a branch protection rule for `REL2_x_STABLE`
3. Enable:
   - "Require status checks to pass before merging"
   - Select all CI jobs as required checks
   - "Require branches to be up to date before merging"

## PostgreSQL Installation

### Linux (APT)
Uses the official PostgreSQL APT repository:
```bash
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y postgresql-17 postgresql-server-dev-17
```

### macOS (Homebrew)
```bash
brew install postgresql@17
# Intel path
export PATH="/usr/local/opt/postgresql@17/bin:$PATH"
# ARM64 path
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
```

### Windows (Chocolatey)
```powershell
choco install postgresql17 -y --params '/Password:postgres'
$env:PATH = "C:\Program Files\PostgreSQL\17\bin;$env:PATH"
```

## Build Commands

### Linux/macOS
```bash
make clean all
sudo make install
make check  # Run regression tests
```

### Windows
```powershell
mkdir build && cd build
cmake -G "Visual Studio 17 2022" -DPG_CONFIG="C:\Program Files\PostgreSQL\17\bin\pg_config.exe" ..
cmake --build . --config Release
```

## Troubleshooting

### PostgreSQL Version Not Available
If a PostgreSQL version is not available in the package manager:
- The matrix uses `fail-fast: false`, so other jobs continue
- Check the job logs for specific error messages
- PostgreSQL 18 may have delayed availability after release

### Submodule Clone Failures
All submodules use HTTPS URLs (not SSH) to avoid authentication issues in CI.
If submodule checkout fails:
1. Verify the submodule URL in `.gitmodules`
2. Check if the submodule repository is public

### Windows Build Failures
Windows builds use CMake with Visual Studio 2022:
- Ensure `pg_config.exe` is in PATH
- Check that `postgres.lib` exists in the PostgreSQL lib directory
- Review CMakeLists.txt for platform-specific settings

### Test Failures
On failure, test artifacts are uploaded:
- `regression_output/` - Contains diff files showing expected vs actual output
- `log/` - PostgreSQL server logs

Access these in the Actions tab under the failed job's artifacts.
