# Feature: Distribute pglogical_create_subscriber

**Target**: pglogical 2.5.1
**Status**: Proposal

## Overview

Include the `pglogical_create_subscriber` executable in all release packages. Currently this utility is built but not distributed, requiring users to build from source.

## Problem Statement

`pglogical_create_subscriber` is a CLI tool that creates a new pglogical subscriber from a physical base backup. It's useful for:
- Fast subscriber setup for large databases (physical backup + logical replication)
- Setting up read replicas
- Migration scenarios

Currently:
- The executable is built by both Makefile and CMake
- It is **not included** in any release artifacts:
  - Windows MSI: Only includes DLLs and SQL files
  - Windows ZIP: Only includes DLLs and SQL files
  - Linux tar.gz: Only includes .so files and SQL files
  - macOS tar.gz: Only includes .dylib/.so files and SQL files

Users must build from source to get this utility.

## Solution

Update the release packaging to include `pglogical_create_subscriber` in all distribution formats.

## Installation Paths

| Platform | Executable Location |
|----------|---------------------|
| Windows MSI | `C:\Program Files\PostgreSQL\{ver}\bin\pglogical_create_subscriber.exe` |
| Windows ZIP | `bin\pglogical_create_subscriber.exe` |
| Linux tar.gz | `bin/pglogical_create_subscriber` |
| macOS tar.gz | `bin/pglogical_create_subscriber` |

## Implementation

### 1. MSI Installer Updates

Update `packaging/windows/pglogical.wxs`:

```xml
<!-- Add bin directory to directory structure -->
<StandardDirectory Id="ProgramFiles64Folder">
  <Directory Id="PostgreSQLFolder" Name="PostgreSQL">
    <Directory Id="POSTGRESQLDIR" Name="$(var.PG_VERSION)">
      <Directory Id="BINDIR" Name="bin" />      <!-- ADD THIS -->
      <Directory Id="LIBDIR" Name="lib" />
      <Directory Id="SHAREDIR" Name="share">
        <Directory Id="EXTENSIONDIR" Name="extension" />
      </Directory>
    </Directory>
  </Directory>
</StandardDirectory>

<!-- Add executable component group -->
<ComponentGroup Id="Executables" Directory="BINDIR">
  <Component Id="pglogical_create_subscriber_exe" Guid="*">
    <File Id="pglogical_create_subscriber.exe"
          Source="$(var.BuildDir)\pglogical_create_subscriber.exe"
          KeyPath="yes" />
  </Component>
</ComponentGroup>

<!-- Add to Feature -->
<Feature Id="Complete" ...>
  <ComponentGroupRef Id="Libraries" />
  <ComponentGroupRef Id="Extensions" />
  <ComponentGroupRef Id="SqlFiles" />
  <ComponentGroupRef Id="UpgradeSqlFiles" />
  <ComponentGroupRef Id="Executables" />    <!-- ADD THIS -->
</Feature>
```

### 2. Release Workflow Updates

Update `.github/workflows/release.yml`:

#### Windows ZIP Packaging

```yaml
- name: Package artifact (Windows ZIP)
  shell: powershell
  run: |
    # ... existing setup ...

    # Create bin directory and copy executable
    New-Item -ItemType Directory -Force -Path "${PACKAGE_DIR}\bin"
    Copy-Item "build\Release\pglogical_create_subscriber.exe" "${PACKAGE_DIR}\bin\"

    # ... rest of packaging ...
```

#### Linux Packaging

```yaml
- name: Package artifact (Linux)
  run: |
    # ... existing setup ...

    # Create bin directory and copy executable
    mkdir -p "${PACKAGE_DIR}/bin"
    cp pglogical_create_subscriber "${PACKAGE_DIR}/bin/"

    # ... rest of packaging ...
```

#### macOS Packaging

```yaml
- name: Package artifact (macOS)
  run: |
    # ... existing setup ...

    # Create bin directory and copy executable
    mkdir -p "${PACKAGE_DIR}/bin"
    cp pglogical_create_subscriber "${PACKAGE_DIR}/bin/"

    # ... rest of packaging ...
```

### 3. Unix Install Script Updates

Update `packaging/unix/install.sh`:

```bash
# Get PostgreSQL directories
PKGLIBDIR=$("$PG_CONFIG" --pkglibdir)
SHAREDIR=$("$PG_CONFIG" --sharedir)
BINDIR=$("$PG_CONFIG" --bindir)    # ADD THIS

# ... existing installation ...

# Install executables (if present)
if [ -d "$SCRIPT_DIR/bin" ]; then
    echo "Installing executables..."
    $NEED_SUDO cp "$SCRIPT_DIR"/bin/* "$BINDIR/"
fi
```

## Updated Package Contents

### Windows ZIP/MSI
```
pglogical-2.5.1-pg17-windows-x64/
├── bin/
│   └── pglogical_create_subscriber.exe    # NEW
├── lib/
│   ├── pglogical.dll
│   └── pglogical_output.dll
├── share/
│   └── extension/
│       ├── pglogical.control
│       ├── pglogical--2.5.1.sql
│       └── pglogical--*.sql
└── README.md
```

### Linux tar.gz
```
pglogical-2.5.1-pg17-linux-x64/
├── bin/
│   └── pglogical_create_subscriber        # NEW
├── lib/
│   ├── pglogical.so
│   └── pglogical_output.so
├── share/
│   └── extension/
│       ├── pglogical.control
│       └── pglogical--*.sql
├── install.sh
└── README.md
```

### macOS tar.gz
```
pglogical-2.5.1-pg17-macos-arm64/
├── bin/
│   └── pglogical_create_subscriber        # NEW
├── lib/
│   ├── pglogical.dylib
│   └── pglogical_output.dylib
├── share/
│   └── extension/
│       ├── pglogical.control
│       └── pglogical--*.sql
├── install.sh
└── README.md
```

## Testing

1. **Build verification**: Ensure `pglogical_create_subscriber` builds on all platforms
2. **Package verification**: Confirm executable is present in ZIP/tar.gz artifacts
3. **MSI verification**: Install MSI and verify executable exists in `bin/` directory
4. **Functional test**: Run `pglogical_create_subscriber --help` after installation

## Checklist

- [ ] Update `packaging/windows/pglogical.wxs` with BINDIR and Executables component
- [ ] Update `.github/workflows/release.yml` Windows ZIP packaging
- [ ] Update `.github/workflows/release.yml` Linux packaging
- [ ] Update `.github/workflows/release.yml` macOS packaging
- [ ] Update `packaging/unix/install.sh` to install executables
- [ ] Update `packaging/windows/README.md` to mention the executable
- [ ] Update `packaging/unix/README.md` to mention the executable
- [ ] Test MSI installation on Windows
- [ ] Test tar.gz installation on Linux
- [ ] Test tar.gz installation on macOS

## Documentation Updates

Update READMEs to mention the bundled executable:

```markdown
## Included Components

- `pglogical.dll` / `pglogical.so` - Main extension library
- `pglogical_output.dll` / `pglogical_output.so` - Output plugin
- `pglogical_create_subscriber` - CLI tool for creating subscribers from base backup
- SQL files for extension installation and upgrades
```

## References

- Source: `pglogical_create_subscriber.c` (~1800 lines)
- Documentation: `docs/README.md` section on `pglogical_create_subscriber`
- Test: `t/010_pglogical_create_subscriber.pl`
