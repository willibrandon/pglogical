# Research: Distribute pglogical_create_subscriber

**Feature Branch**: `003-distribute-create-subscriber`
**Date**: 2026-01-08

## Overview

This document captures research findings for including `pglogical_create_subscriber` in all release packages.

## Research Areas

### 1. Current Build Process

**Decision**: Use existing build outputs; no build changes required

**Rationale**:
- The `pglogical_create_subscriber` executable is already built by both Makefile (line 172-173) and CMakeLists.txt (lines 203-241)
- Linux/macOS: Built via `make` targeting `pglogical_create_subscriber`
- Windows: Built via CMake as `pglogical_create_subscriber.exe`
- Dependencies (libpq, pgport, pgcommon) are already linked

**Alternatives Considered**:
- Separate build target for packaging: Rejected (already builds with extension)
- Static linking: Rejected (would increase binary size, PostgreSQL provides runtime libs)

### 2. WiX v5 Packaging Patterns

**Decision**: Add new ComponentGroup for BINDIR with exe file

**Rationale**:
- WiX v5 uses standardized folder IDs (`BINDIR` available via `<StandardDirectory>`)
- Existing pattern in `pglogical.wxs` uses ComponentGroups (e.g., `Libraries`, `ExtensionFiles`)
- Follow the same pattern: define `Executables` ComponentGroup referencing BINDIR

**Key WiX v5 Elements**:
```xml
<StandardDirectory Id="BINDIR">
  <Component Id="Executables" Guid="*">
    <File Source="$(BuildDir)/pglogical_create_subscriber.exe" />
  </Component>
</StandardDirectory>
```

**Alternatives Considered**:
- Custom property for path: Rejected (BINDIR standard folder is cleaner)
- Include in existing Libraries component: Rejected (different target directory)

### 3. GitHub Actions Packaging

**Decision**: Add bin/ directory to package structure, copy executable before archiving

**Rationale**:
- All platforms follow same package structure pattern
- Extend existing script sections that handle lib/ and share/extension/
- Add `mkdir -p ${PACKAGE_DIR}/bin` followed by executable copy

**Windows-specific**:
- Build output in `build/Release/pglogical_create_subscriber.exe`
- Already in PATH for CMake builds

**Linux/macOS**:
- Build output is `pglogical_create_subscriber` (no extension)
- Located in repository root after `make`

**Alternatives Considered**:
- Separate packaging job: Rejected (adds complexity, existing jobs sufficient)
- Post-build script: Rejected (inline in workflow is simpler)

### 4. Install Script Enhancement

**Decision**: Add BINDIR detection and executable installation to install.sh

**Rationale**:
- `pg_config --bindir` provides correct PostgreSQL bin directory
- Follow existing pattern: check for write permissions, use sudo if needed
- Copy executables from package bin/ to PostgreSQL bin/

**Implementation Pattern**:
```bash
BINDIR=$(${PG_CONFIG} --bindir)
# Install executables
if [ -d "${SCRIPT_DIR}/bin" ]; then
  for exe in "${SCRIPT_DIR}/bin/"*; do
    install_file "$exe" "${BINDIR}/$(basename "$exe")"
  done
fi
```

**Alternatives Considered**:
- Symlink instead of copy: Rejected (users may delete extracted package)
- Separate install command: Rejected (unified install.sh is simpler)

### 5. Documentation Updates

**Decision**: Add executable mention to both README files

**Rationale**:
- FR-007 requires documentation mention
- Users should know the utility is available and its purpose
- Both packaging/unix/README.md and packaging/windows/README.md need updates

**Content to Add**:
- Brief description of utility purpose
- Installation location (bin directory)
- Basic usage example (`--help`)

### 6. Testing Strategy

**Decision**: Rely on existing TAP test + acceptance testing via --help

**Rationale**:
- `t/010_pglogical_create_subscriber.pl` already tests full functionality
- SC-002 requires `--help` works within 1 minute of installation
- CI workflow runs regression tests including TAP tests
- Manual acceptance: verify package contents and --help output

**Alternatives Considered**:
- Add packaging-specific test: Rejected (--help verification sufficient)
- Automated package extraction test: Consider for future (not in scope)

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Executable not found in build output | High | Verified in CMakeLists.txt and Makefile |
| WiX component breaks MSI build | Medium | Test MSI locally before release |
| Install script fails on permissions | Low | Existing sudo pattern handles this |
| PATH issues on Windows | Low | PostgreSQL bin is typically in PATH |

## Dependencies Confirmed

- WiX Toolset v5: Already configured in release.yml
- pg_config: Available on all platforms after PostgreSQL install
- GitHub Actions runners: Already have required tools
- No new external dependencies required

## Conclusion

All research areas resolved. The implementation is straightforward:

1. **release.yml**: Add bin/ directory creation and executable copy (4 locations: Linux, macOS, Windows ZIP, post-build)
2. **pglogical.wxs**: Add BINDIR component with executable
3. **install.sh**: Add BINDIR detection and executable installation
4. **READMEs**: Add documentation for bundled executable
