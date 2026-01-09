# Quickstart: Distribute pglogical_create_subscriber

**Feature Branch**: `003-distribute-create-subscriber`
**Date**: 2026-01-08

## What This Feature Does

After implementation, the `pglogical_create_subscriber` utility will be included in all pglogical release packages. Users can use it immediately after installing pglogical.

## Installation Verification

After installing pglogical from any package:

```bash
# Verify the utility is installed
pglogical_create_subscriber --help
```

Expected output includes usage information and available options.

## Package Contents After Implementation

### Windows MSI
- Installs to: `C:\Program Files\PostgreSQL\{version}\bin\pglogical_create_subscriber.exe`
- Available immediately after MSI installation

### Windows ZIP
```text
pglogical-{version}-pg{pg_version}-windows-x64/
├── bin/
│   └── pglogical_create_subscriber.exe  # NEW
├── lib/
│   ├── pglogical.dll
│   └── pglogical_output.dll
└── share/extension/
    └── (extension files)
```

### Linux tar.gz
```text
pglogical-{version}-pg{pg_version}-linux-x64/
├── bin/
│   └── pglogical_create_subscriber  # NEW
├── lib/
│   ├── pglogical.so
│   └── pglogical_output.so
├── share/extension/
│   └── (extension files)
└── install.sh  # Installs bin/ contents too
```

### macOS tar.gz
```text
pglogical-{version}-pg{pg_version}-macos-arm64/
├── bin/
│   └── pglogical_create_subscriber  # NEW
├── lib/
│   ├── pglogical.dylib (or .so)
│   └── pglogical_output.dylib (or .so)
├── share/extension/
│   └── (extension files)
└── install.sh  # Installs bin/ contents too
```

## Development Testing

To test locally before release:

### Build and Verify (Linux/macOS)
```bash
make clean all
ls -la pglogical_create_subscriber
./pglogical_create_subscriber --help
```

### Build and Verify (Windows)
```powershell
cmake -B build -G "Visual Studio 17 2022"
cmake --build build --config Release
.\build\Release\pglogical_create_subscriber.exe --help
```

### Test Package Structure
```bash
# After packaging, extract and verify
tar -tzf pglogical-*.tar.gz | grep bin/
```

## Files Modified

| File | Purpose |
|------|---------|
| `.github/workflows/release.yml` | Add bin/ to package structure |
| `packaging/windows/pglogical.wxs` | Add exe to MSI installer |
| `packaging/unix/install.sh` | Install bin/ contents |
| `packaging/unix/README.md` | Document bundled utility |
| `packaging/windows/README.md` | Document bundled utility |

## Success Criteria Checklist

- [ ] Windows MSI includes pglogical_create_subscriber.exe in bin
- [ ] Windows ZIP has bin/pglogical_create_subscriber.exe
- [ ] Linux tar.gz has bin/pglogical_create_subscriber
- [ ] macOS tar.gz has bin/pglogical_create_subscriber
- [ ] install.sh copies executable to PostgreSQL bin
- [ ] READMEs mention the bundled utility
- [ ] `--help` works after installation
