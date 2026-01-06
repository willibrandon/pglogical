# Quickstart: GitHub Releases Distribution Implementation

**Date**: 2026-01-05
**Feature**: [spec.md](./spec.md)

## Prerequisites

- Git with access to pglogical repository
- GitHub repository with Actions enabled
- Understanding of GitHub Actions workflow syntax

## Directory Structure

After implementation, the repository will have:

```
pglogical/
├── .github/
│   └── workflows/
│       ├── ci.yml              # PR/push continuous integration
│       └── release.yml         # Tag-triggered release pipeline
├── packaging/
│   ├── windows/
│   │   ├── pglogical.wxs       # WiX v5 MSI installer definition
│   │   └── README.md           # Windows installation instructions
│   └── unix/
│       └── install.sh          # Linux/macOS installation helper
└── ... (existing files)
```

## Implementation Order

### Phase 1: CI Workflow (ci.yml)

1. Create `.github/workflows/ci.yml`
2. Configure checkout with `submodules: recursive`
3. Set up build matrix (PG 13-18 × 4 platforms)
4. Add platform-specific PostgreSQL installation steps
5. Add build steps (make for Linux/macOS, cmake for Windows)
6. Add test steps (regression tests on Linux/macOS)
7. Test with a PR

### Phase 2: Unix Packaging

1. Create `packaging/unix/install.sh`
2. Implement pg_config detection
3. Implement sudo elevation for privileged directories
4. Test on local Linux/macOS machines

### Phase 3: Windows Packaging

1. Create `packaging/windows/pglogical.wxs`
2. Implement registry search for PostgreSQL path
3. Implement directory browse fallback
4. Configure MajorUpgrade for clean upgrades
5. Configure unique UpgradeCode per PG version
6. Create `packaging/windows/README.md`
7. Test MSI build locally with WiX v5

### Phase 4: Release Workflow (release.yml)

1. Create `.github/workflows/release.yml`
2. Add build jobs (same as CI)
3. Add source archive creation job
4. Add release job with:
   - Artifact download
   - Checksum generation
   - GitHub Release creation
   - Asset attachment
5. Test with a test tag (e.g., `v2.5.0-test1`)

### Phase 5: Integration Testing

1. Create a prerelease tag
2. Verify all artifacts build
3. Verify GitHub Release creation
4. Verify artifact downloads work
5. Test installation on each platform

## Key Commands

### Local Development

```bash
# Build extension
make clean all

# Install locally
sudo make install

# Run regression tests
make check
```

### Testing CI Locally (act)

```bash
# Install act (GitHub Actions local runner)
brew install act  # macOS

# Run CI workflow locally
act push --job build
```

### Creating a Release

```bash
# Create and push a release tag
git tag v2.5.0
git push origin v2.5.0

# Create a prerelease tag
git tag v2.5.0-beta1
git push origin v2.5.0-beta1
```

### Building MSI Locally

```powershell
# Install WiX v5
dotnet tool install --global wix --version 5.0.0

# Build MSI
wix build -o pglogical-pg17.msi packaging/windows/pglogical.wxs -d PG_VERSION=17 -d VERSION=2.5.0
```

## Verification Checklist

After implementation, verify:

- [ ] CI runs on PR creation
- [ ] CI runs on push to REL2_x_STABLE
- [ ] All 24 matrix jobs complete (6 PG versions × 4 platforms)
- [ ] Release workflow triggers on `v*` tag push
- [ ] All artifacts attach to GitHub Release
- [ ] checksums.txt contains all artifact hashes
- [ ] Prerelease tags create prerelease releases
- [ ] MSI installer detects PostgreSQL path
- [ ] install.sh works on Linux and macOS
- [ ] Source archives include submodule contents

## Troubleshooting

### CI Job Failures

1. Check workflow logs in GitHub Actions tab
2. Look for PostgreSQL installation errors
3. Verify pg_config is in PATH for build steps

### MSI Build Failures

1. Verify WiX v5 is installed (`dotnet tool list -g`)
2. Check WiX build output for missing files
3. Verify registry search key matches installed PostgreSQL

### Release Asset Upload Failures

1. Check GITHUB_TOKEN permissions
2. Verify artifact names don't contain invalid characters
3. Check for duplicate asset names
