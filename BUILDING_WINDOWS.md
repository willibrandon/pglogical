# Building pglogical on Windows

## Prerequisites

1. **Visual Studio 2022** (or later) with C++ build tools
2. **CMake** 3.14 or later
3. **PostgreSQL** installation with development files (headers and libraries)

The easiest way to get PostgreSQL with development files is to download the Windows binaries from:
https://www.enterprisedb.com/downloads/postgres-postgresql-downloads

## Build Instructions

### 1. Ensure pg_config is in your PATH

```powershell
$env:PATH = "C:\path\to\postgresql\bin;$env:PATH"
pg_config --version
```

### 2. Configure with CMake

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
```

Or specify pg_config explicitly:

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DPG_CONFIG="C:\path\to\postgresql\bin\pg_config.exe"
```

### 3. Build

```powershell
cmake --build build --config Release
```

### 4. Install

```powershell
cmake --install build --config Release
```

This installs to the PostgreSQL installation directory detected by pg_config.

## Build Output

After a successful build, you'll find in `build/Release/`:

| File | Description |
|------|-------------|
| pglogical.dll | Main extension |
| pglogical_output.dll | Output plugin (backwards compatibility) |
| pglogical_create_subscriber.exe | Subscriber creation utility |

## Supported PostgreSQL Versions

The CMake build supports PostgreSQL 9.4 through 18, automatically selecting the appropriate compatibility layer based on the detected version.

## Troubleshooting

### pg_config not found
Ensure the PostgreSQL bin directory is in your PATH, or pass `-DPG_CONFIG=...` to cmake.

### Missing postgres.lib
The PostgreSQL installation must include development files. The EDB Windows binaries include these by default.

### Link errors for pgport/pgcommon
The `pglogical_create_subscriber` utility requires `libpgport.a` and `libpgcommon.a`. These are included in the EDB distribution. If missing, the DLLs will still build but the utility will not.
