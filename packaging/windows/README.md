# pglogical - Logical Replication Extension for PostgreSQL

## Installation Instructions for Windows

### Option 1: MSI Installer (Recommended)

1. Download the MSI installer for your PostgreSQL version
   - Example: `pglogical-2.5.0-pg17-windows-x64.msi`

2. Run the installer
   - It will automatically detect your PostgreSQL installation directory
   - If not found, you can browse to select the correct directory

3. The installer copies files to:
   - `bin\pglogical_create_subscriber.exe`
   - `lib\pglogical.dll`
   - `lib\pglogical_output.dll`
   - `share\extension\pglogical.control`
   - `share\extension\pglogical--*.sql`

4. To uninstall, use Windows Add/Remove Programs

### Option 2: Manual Installation (ZIP Package)

1. Download the ZIP package for your PostgreSQL version
   - Example: `pglogical-2.5.0-pg17-windows-x64.zip`

2. Extract the ZIP to a temporary location

3. Copy files to your PostgreSQL installation directory:
   - Copy `bin\*.exe` to: `C:\Program Files\PostgreSQL\17\bin\`
   - Copy `lib\*.dll` to: `C:\Program Files\PostgreSQL\17\lib\`
   - Copy `share\extension\*` to: `C:\Program Files\PostgreSQL\17\share\extension\`

   **PowerShell example:**
   ```powershell
   $PG_DIR = "C:\Program Files\PostgreSQL\17"
   Copy-Item "bin\*.exe" "$PG_DIR\bin\"
   Copy-Item "lib\*.dll" "$PG_DIR\lib\"
   Copy-Item "share\extension\*" "$PG_DIR\share\extension\"
   ```

## Bundled Utilities

### pglogical_create_subscriber

The `pglogical_create_subscriber.exe` utility creates a new pglogical subscriber node from a physical base backup. This enables fast subscriber setup for large databases by combining physical backup with logical replication.

**Usage:**
```powershell
# After installation, verify the utility is available
pglogical_create_subscriber --help
```

The utility is installed to the PostgreSQL bin directory alongside other PostgreSQL tools like `psql.exe` and `pg_dump.exe`.

## Enabling the Extension

After installation, enable pglogical in your database:

```sql
CREATE EXTENSION pglogical;
```

To verify the installation:

```sql
SELECT pglogical.pglogical_version();
```

## Configuration

pglogical requires these PostgreSQL settings in `postgresql.conf`:

1. Add pglogical to shared_preload_libraries:
   ```
   shared_preload_libraries = 'pglogical'
   ```

2. Set wal_level to 'logical':
   ```
   wal_level = 'logical'
   ```

3. Increase max_worker_processes (at least 2 per database):
   ```
   max_worker_processes = 10
   ```

4. Increase max_replication_slots:
   ```
   max_replication_slots = 10
   ```

5. Increase max_wal_senders:
   ```
   max_wal_senders = 10
   ```

After changing `postgresql.conf`, restart the PostgreSQL service.

## Troubleshooting

### "could not load library pglogical"

- Verify `pglogical.dll` is in the PostgreSQL lib directory
- Check Windows Event Viewer for detailed error messages

### "extension pglogical does not exist"

- Verify `.control` and `.sql` files are in `share\extension` directory
- Check file permissions

### PostgreSQL service won't start

- Check `postgresql.conf` syntax
- Review PostgreSQL log files in the data directory

## Documentation

- Full documentation: https://github.com/2ndQuadrant/pglogical
- Report issues: https://github.com/2ndQuadrant/pglogical/issues
