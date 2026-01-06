# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## MANDATORY: Implementation Requirements

**These rules are NON-NEGOTIABLE and override all other considerations.**

### No Deferred Work

- ALL implementations MUST be complete and fully functional
- Placeholder code, stub functions, and TODO comments are FORBIDDEN
- Code that returns dummy values or skips implementation logic is NOT ACCEPTABLE
- If you cannot fully implement something, STOP and ask - do not create partial implementations
- A task is either 100% complete or it is not done at all

### Full Test Implementation Required

- ALL features MUST include complete regression tests
- Test complexity is NEVER a valid excuse to simplify or skip tests
- Conflict-related features MUST include full conflict scenario tests with actual provider/subscriber replication setup
- Tests MUST exercise the complete code path, not just schema or configuration validation
- If a test requires complex multi-node setup, that setup MUST be implemented
- Refer to existing tests like `sql/basic.sql` and `sql/conflict_secondary_unique.sql` for proper test patterns

### Violations

Any of the following will result in rejected work:
- Functions containing `/* TODO */` or similar deferred work markers
- Stub implementations that don't perform actual logic
- Tests that only check schema existence instead of actual functionality
- "Simplified" tests that skip replication verification
- Partial implementations with plans to "complete later"

## Build Commands

```bash
# Build (requires pg_config in PATH)
make clean all

# Install to PostgreSQL
sudo make install

# Run regression tests (installs first, uses temp instance)
make check

# Run specific regression test
make installcheck REGRESS=basic

# Build for specific PostgreSQL version
PATH=/usr/pgsql-17/bin:$PATH make clean all
```

## Architecture Overview

pglogical is a PostgreSQL extension providing logical replication using a publish/subscribe model.

### Core Components

**Provider Side (WAL Decoding)**
- `pglogical_output_plugin.c` - Logical decoding output plugin, converts WAL to replication messages
- `pglogical_proto_native.c` / `pglogical_proto_json.c` - Wire protocol serialization
- `pglogical_repset.c` - Replication set management (table/sequence filtering)

**Subscriber Side (Apply Worker)**
- `pglogical_apply.c` - Main apply worker, processes incoming replication stream
- `pglogical_apply_heap.c` - Low-level tuple application using direct heap access
- `pglogical_apply_spi.c` - Alternative apply path using SPI (SQL interface)
- `pglogical_conflict.c` - Conflict detection and resolution
- `pglogical_sync.c` - Initial data synchronization

**Shared Infrastructure**
- `pglogical.c` - Extension initialization, GUC variables, shared memory
- `pglogical_worker.c` - Background worker management
- `pglogical_node.c` - Node and subscription catalog operations
- `pglogical_functions.c` - SQL-callable functions

### Version Compatibility Layer

Each `compat{NN}/` directory contains `pglogical_compat.c` and `pglogical_compat.h` for PostgreSQL version-specific code. The Makefile auto-selects based on `pg_config --version`. When using PostgreSQL APIs that changed between versions, add version guards:

```c
#if PG_VERSION_NUM >= 150000
    // PG 15+ code path
#else
    // Older versions
#endif
```

### Extension SQL Schema

- `pglogical--X.Y.Z.sql` - Full schema for fresh installs
- `pglogical--X.Y.Z--A.B.C.sql` - Upgrade scripts between versions
- Schema objects live in the `pglogical` schema

### Key Data Structures

- `PGLogicalSubscription` - Subscription state (defined in `pglogical_node.h`)
- `PGLogicalRelation` - Replicated table metadata (defined in `pglogical_relcache.h`)
- `PGLogicalConflictResolution` - Conflict resolution outcomes (defined in `pglogical_conflict.h`)

## Testing

Regression tests are in `sql/` with expected output in `expected/`. Tests require a running PostgreSQL instance and create temporary provider/subscriber nodes.

```bash
# Run all tests
make check

# Run single test file
make installcheck REGRESS=conflict_secondary_unique
```

## Configuration

Key GUC variables (set in postgresql.conf or via ALTER SYSTEM):
- `pglogical.conflict_resolution` - How to resolve conflicts (apply_remote, keep_local, etc.)
- `pglogical.use_spi` - Use SPI instead of direct heap access for apply
- `pglogical.batch_inserts` - Enable batch insert optimization

## Active Technologies
- YAML (GitHub Actions workflows), WiX v5 (MSI definitions), Bash (install scripts), PowerShell (Windows CI), Make (existing build system) + GitHub Actions runners (ubuntu-latest, windows-2022, macos-13, macos-14), WiX Toolset v5 (.NET global tool), PostgreSQL development headers, Visual Studio 2022 Build Tools, Homebrew (macOS), apt/Chocolatey (package managers) (002-github-releases)
- N/A (artifacts stored as GitHub Release assets) (002-github-releases)

## Recent Changes
- 002-github-releases: Added YAML (GitHub Actions workflows), WiX v5 (MSI definitions), Bash (install scripts), PowerShell (Windows CI), Make (existing build system) + GitHub Actions runners (ubuntu-latest, windows-2022, macos-13, macos-14), WiX Toolset v5 (.NET global tool), PostgreSQL development headers, Visual Studio 2022 Build Tools, Homebrew (macOS), apt/Chocolatey (package managers)
