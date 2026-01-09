# Unix Installation Package

This directory contains the installation helper script for Linux and macOS.

## Contents

- `install.sh` - Installation script that copies pglogical files to PostgreSQL directories

## Usage

### Basic Installation

```bash
# Extract the package
tar -xzf pglogical-2.5.0-pg17-linux-x64.tar.gz
cd pglogical-2.5.0-pg17-linux-x64

# Run the install script (uses pg_config from PATH)
./install.sh
```

### Custom pg_config Location

If pg_config is not in your PATH, specify it via environment variable:

```bash
PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config ./install.sh
```

### Custom PostgreSQL Directory

Alternatively, specify the PostgreSQL installation directory directly:

```bash
PGDIR=/usr/lib/postgresql/17 ./install.sh
```

This is useful when pg_config is not available or you want to install to a specific PostgreSQL installation.

### What the Script Does

1. Determines PostgreSQL directories using one of:
   - `PGDIR` environment variable (direct path to PostgreSQL installation)
   - `PG_CONFIG` environment variable (path to pg_config executable)
   - `pg_config` from PATH
2. Copies executables to PostgreSQL `bin/` directory
3. Copies shared libraries to `lib/` directory
4. Copies extension files to `share/extension/` directory
5. Uses sudo automatically if target directories require elevated permissions

## Package Contents

A typical package contains:

```
pglogical-2.5.0-pg17-linux-x64/
├── install.sh                    # This installation script
├── bin/
│   └── pglogical_create_subscriber  # Subscriber creation utility
├── lib/
│   ├── pglogical.so              # Main extension library
│   └── pglogical_output.so       # Output plugin library
└── share/
    └── extension/
        ├── pglogical.control     # Extension control file
        ├── pglogical--2.5.0.sql  # Extension SQL
        ├── pglogical--*.sql      # Upgrade scripts
        ├── pglogical_origin.control
        └── pglogical_origin--1.0.0.sql
```

## Bundled Utilities

### pglogical_create_subscriber

The `pglogical_create_subscriber` utility creates a new pglogical subscriber node from a physical base backup. This enables fast subscriber setup for large databases by combining physical backup with logical replication.

**Usage:**
```bash
# After installation, verify the utility is available
pglogical_create_subscriber --help
```

The utility is installed to the PostgreSQL bin directory alongside other PostgreSQL tools like `psql` and `pg_dump`.

## Post-Installation

After installation, enable the extension in your database:

```sql
CREATE EXTENSION pglogical;
```

## Requirements

- PostgreSQL development installation (pg_config must be available)
- Bash 3.2 or later (default on macOS and most Linux distributions)
- Standard coreutils (install, cp, mkdir)

## Troubleshooting

### pg_config not found

Either add PostgreSQL bin directory to your PATH, or use PGDIR:

```bash
# Option 1: Add to PATH
# Linux (APT installation)
export PATH=/usr/lib/postgresql/17/bin:$PATH

# macOS (Homebrew on Intel)
export PATH=/usr/local/opt/postgresql@17/bin:$PATH

# macOS (Homebrew on Apple Silicon)
export PATH=/opt/homebrew/opt/postgresql@17/bin:$PATH

# Option 2: Use PGDIR directly
PGDIR=/usr/lib/postgresql/17 ./install.sh
```

### Permission denied

The script automatically uses sudo when needed. If it still fails:

```bash
sudo ./install.sh
```

### Extension not found after installation

Verify files were copied correctly:

```bash
ls $(pg_config --pkglibdir)/pglogical*
ls $(pg_config --sharedir)/extension/pglogical*
```
