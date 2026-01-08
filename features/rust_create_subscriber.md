# pglogical_create_subscriber Rust Rewrite

**Target**: pglogical 2.6.0
**Author**: Brandon
**Status**: Design Proposal

## Overview

Rewrite `pglogical_create_subscriber` from C to Rust as a standalone CLI tool. This is the recommended first step in incrementally porting pglogical to Rust, as it has zero coupling to the PostgreSQL extension runtime and can be developed/tested independently.

## Problem Statement

The current C implementation (`pglogical_create_subscriber.c`, ~1800 lines) has several limitations:

1. **Error handling** - Uses `die()` for all errors, no recovery or cleanup
2. **Memory safety** - Manual memory management with potential leaks
3. **Platform differences** - `#ifdef WIN32` scattered throughout
4. **No async I/O** - Blocking operations with manual polling loops
5. **Limited testing** - Hard to unit test due to tight coupling
6. **Maintenance burden** - C code alongside Rust extension (future)

## Solution

Create a Rust CLI binary (`pglogical-create-subscriber`) that:
- Provides identical functionality to the C version
- Uses modern async Rust for database connections
- Has proper error handling with actionable messages
- Is cross-platform without conditional compilation
- Can be thoroughly unit and integration tested
- Ships alongside the C version initially, then replaces it

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     pglogical-create-subscriber (Rust)                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │    CLI      │  │  Provider   │  │ Subscriber  │  │   Config    │       │
│  │   (clap)    │  │  Manager    │  │  Manager    │  │   Writer    │       │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘       │
│         │                │                │                │               │
│         └────────────────┴────────────────┴────────────────┘               │
│                                   │                                         │
│                          ┌────────┴────────┐                               │
│                          │   Orchestrator  │                               │
│                          └────────┬────────┘                               │
│                                   │                                         │
│         ┌─────────────────────────┼─────────────────────────┐              │
│         │                         │                         │              │
│         ▼                         ▼                         ▼              │
│  ┌─────────────┐          ┌─────────────┐          ┌─────────────┐        │
│  │  Database   │          │   Process   │          │    File     │        │
│  │   Client    │          │   Runner    │          │   System    │        │
│  │(tokio-postgres)        │ (pg_ctl,    │          │   (std::fs) │        │
│  └─────────────┘          │ basebackup) │          └─────────────┘        │
│                           └─────────────┘                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Current C Implementation Analysis

### Core Functions to Port

| C Function | Lines | Rust Equivalent | Complexity |
|------------|-------|-----------------|------------|
| `main()` | 300+ | `Orchestrator::run()` | High |
| `run_pg_ctl()` | 30 | `ProcessRunner::pg_ctl()` | Low |
| `run_basebackup()` | 30 | `ProcessRunner::basebackup()` | Low |
| `wait_postmaster_connection()` | 40 | `async fn wait_for_connection()` | Medium |
| `wait_primary_connection()` | 30 | `async fn wait_for_primary()` | Medium |
| `get_remote_info()` | 30 | `ProviderManager::get_info()` | Low |
| `initialize_replication_slot()` | 70 | `ProviderManager::create_slot()` | Medium |
| `pglogical_subscribe()` | 60 | `SubscriberManager::subscribe()` | Medium |
| `remove_unwanted_data()` | 30 | `SubscriberManager::cleanup()` | Low |
| `initialize_replication_origin()` | 50 | `SubscriberManager::init_origin()` | Medium |
| `create_restore_point()` | 20 | `ProviderManager::create_restore_point()` | Low |
| `WriteRecoveryConf()` | 40 | `ConfigWriter::write_recovery()` | Low |
| `get_connstr()` | 80 | `ConnectionString::parse/build()` | Medium |
| `read_sysid()` | 30 | `ControlFile::read_sysid()` | Low |

### Data Structures to Port

```rust
// C struct
typedef struct RemoteInfo {
    Oid         nodeid;
    char       *node_name;
    char       *sysid;
    char       *dbname;
    char       *replication_sets;
} RemoteInfo;

// Rust equivalent
#[derive(Debug, Clone)]
pub struct RemoteInfo {
    pub node_id: u32,
    pub node_name: String,
    pub sysid: String,
    pub dbname: String,
    pub replication_sets: Vec<String>,
}
```

## Implementation

### Crate Dependencies

```toml
[package]
name = "pglogical-create-subscriber"
version = "2.6.0"
edition = "2021"
rust-version = "1.75"

[dependencies]
# CLI
clap = { version = "4", features = ["derive", "env"] }

# Async runtime
tokio = { version = "1", features = ["full"] }

# PostgreSQL client
tokio-postgres = "0.7"
postgres-types = { version = "0.2", features = ["derive"] }

# Error handling
anyhow = "1"
thiserror = "1"

# Logging
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

# Utilities
serde = { version = "1", features = ["derive"] }
serde_json = "1"

[dev-dependencies]
tempfile = "3"
assert_cmd = "2"
predicates = "3"
```

### Project Structure

```
pglogical/
├── pglogical.c                   # Existing C extension (root level)
├── pglogical_apply.c
├── pglogical_conflict.c
├── pglogical_create_subscriber.c # C version (to be replaced)
├── pglogical_sync.c
├── ... (other C sources)
├── Makefile
├── CMakeLists.txt
│
├── pglogical-cli/                # New Rust CLI crate
│   ├── Cargo.toml
│   ├── src/
│   │   ├── main.rs              # Entry point
│   │   ├── cli.rs               # CLI argument parsing
│   │   ├── config.rs            # Configuration types
│   │   ├── error.rs             # Error types
│   │   ├── orchestrator.rs      # Main workflow
│   │   ├── provider.rs          # Provider operations
│   │   ├── subscriber.rs        # Subscriber operations
│   │   ├── process.rs           # External process runner
│   │   ├── postgres/
│   │   │   ├── mod.rs
│   │   │   ├── client.rs        # Database client wrapper
│   │   │   ├── connstring.rs    # Connection string handling
│   │   │   └── control_file.rs  # pg_control reader
│   │   └── recovery/
│   │       ├── mod.rs
│   │       └── config.rs        # recovery.conf/postgresql.auto.conf
│   └── tests/
│       ├── integration/
│       │   └── full_workflow.rs
│       └── unit/
│           ├── connstring.rs
│           └── control_file.rs
```

### Core Types

#### `src/error.rs`

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum CreateSubscriberError {
    #[error("Connection to provider failed: {0}")]
    ProviderConnection(#[source] tokio_postgres::Error),

    #[error("Connection to subscriber failed: {0}")]
    SubscriberConnection(#[source] tokio_postgres::Error),

    #[error("Provider is not configured as pglogical node")]
    ProviderNotConfigured,

    #[error("pg_basebackup failed with exit code {code}: {stderr}")]
    BasebackupFailed { code: i32, stderr: String },

    #[error("pg_ctl {action} failed with exit code {code}: {stderr}")]
    PgCtlFailed {
        action: String,
        code: i32,
        stderr: String,
    },

    #[error("Replication slot '{0}' already exists")]
    SlotExists(String),

    #[error("Data directory '{0}' is not a valid PostgreSQL data directory")]
    InvalidDataDir(std::path::PathBuf),

    #[error("Subscriber sysid does not match provider (expected {expected}, got {actual})")]
    SysidMismatch { expected: String, actual: String },

    #[error("Timeout waiting for PostgreSQL to {action} after {seconds}s")]
    Timeout { action: String, seconds: u64 },

    #[error("Invalid connection string: {0}")]
    InvalidConnString(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Configuration error: {0}")]
    Config(String),
}

pub type Result<T> = std::result::Result<T, CreateSubscriberError>;
```

#### `src/cli.rs`

```rust
use clap::Parser;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "pglogical_create_subscriber")]
#[command(about = "Initialize a new pglogical subscriber from a physical base backup")]
#[command(version)]
pub struct Cli {
    /// Data directory for the new subscriber
    #[arg(short = 'D', long = "pgdata", required = true)]
    pub data_dir: PathBuf,

    /// Name of the subscriber node
    #[arg(short = 'n', long = "subscriber-name", required = true)]
    pub subscriber_name: String,

    /// Connection string to the provider
    #[arg(long = "provider-dsn", required = true)]
    pub provider_dsn: String,

    /// Connection string for the subscriber (used after creation)
    #[arg(long = "subscriber-dsn", required = true)]
    pub subscriber_dsn: String,

    /// Comma-separated list of replication sets
    #[arg(long = "replication-sets", default_value = "default,default_insert_only,ddl_sql")]
    pub replication_sets: String,

    /// Comma-separated list of databases to replicate
    #[arg(long = "databases")]
    pub databases: Option<String>,

    /// Apply delay in seconds
    #[arg(long = "apply-delay", default_value = "0")]
    pub apply_delay: u32,

    /// Drop existing replication slot if it exists
    #[arg(long = "drop-slot-if-exists")]
    pub drop_slot_if_exists: bool,

    /// Stop the subscriber after initialization
    #[arg(short = 's', long = "stop")]
    pub stop: bool,

    /// Path to custom postgresql.conf
    #[arg(long = "postgresql-conf")]
    pub postgresql_conf: Option<PathBuf>,

    /// Path to custom pg_hba.conf
    #[arg(long = "hba-conf")]
    pub pg_hba_conf: Option<PathBuf>,

    /// Path to custom recovery configuration
    #[arg(long = "recovery-conf")]
    pub recovery_conf: Option<PathBuf>,

    /// Additional arguments to pass to pg_basebackup
    #[arg(long = "extra-basebackup-args")]
    pub extra_basebackup_args: Option<String>,

    /// Use text transfer mode
    #[arg(long = "text-types")]
    pub force_text_transfer: bool,

    /// Verbosity level (-v, -vv, -vvv)
    #[arg(short = 'v', long = "verbose", action = clap::ArgAction::Count)]
    pub verbose: u8,
}

impl Cli {
    /// Parse databases from comma-separated string or connection string
    pub fn get_databases(&self) -> Result<Vec<String>, CreateSubscriberError> {
        if let Some(ref dbs) = self.databases {
            Ok(dbs.split(',').map(|s| s.trim().to_string()).collect())
        } else {
            // Extract dbname from provider_dsn
            let connstr = ConnectionString::parse(&self.provider_dsn)?;
            connstr
                .dbname()
                .map(|db| vec![db.to_string()])
                .ok_or_else(|| {
                    CreateSubscriberError::Config(
                        "Either --databases or dbname in --provider-dsn required".into(),
                    )
                })
        }
    }
}
```

#### `src/orchestrator.rs`

```rust
use crate::{
    cli::Cli,
    error::{CreateSubscriberError, Result},
    process::ProcessRunner,
    provider::ProviderManager,
    subscriber::SubscriberManager,
    recovery::RecoveryConfigWriter,
};
use std::path::Path;
use tracing::{info, debug};

pub struct Orchestrator {
    cli: Cli,
    process: ProcessRunner,
}

impl Orchestrator {
    pub fn new(cli: Cli) -> Self {
        let process = ProcessRunner::new(&cli.data_dir);
        Self { cli, process }
    }

    pub async fn run(&self) -> Result<()> {
        info!("Starting pglogical subscriber creation...");

        let databases = self.cli.get_databases()?;
        let mut slot_names = Vec::with_capacity(databases.len());

        // Phase 1: Connect to provider and create slots
        for (i, db) in databases.iter().enumerate() {
            info!("Getting information for database {}...", db);

            let provider = ProviderManager::connect(&self.cli.provider_dsn, db).await?;
            let remote_info = provider.get_remote_info().await?;

            // First database: check data directory
            if i == 0 {
                self.validate_or_create_data_dir(&remote_info.sysid).await?;
            }

            info!("Creating replication slot in database {}...", db);
            let slot_name = provider
                .create_replication_slot(
                    &self.cli.subscriber_name,
                    self.cli.drop_slot_if_exists,
                )
                .await?;
            slot_names.push(slot_name);
        }

        // Phase 2: Create basebackup if needed
        if !self.data_dir_exists() {
            self.run_basebackup(&databases[0]).await?;
        }

        // Phase 3: Create restore point
        let provider = ProviderManager::connect(&self.cli.provider_dsn, &databases[0]).await?;
        let restore_point = Self::generate_restore_point_name();
        info!("Creating restore point \"{}\"...", restore_point);
        let remote_lsn = provider.create_restore_point(&restore_point).await?;
        drop(provider);

        // Phase 4: Configure and start recovery
        self.configure_recovery(&restore_point).await?;
        self.start_recovery().await?;
        self.wait_for_recovery(&databases[0]).await?;

        // Phase 5: Clean up copied pglogical data
        for db in &databases {
            let subscriber = SubscriberManager::connect(&self.cli.subscriber_dsn, db).await?;
            subscriber.remove_unwanted_data().await?;
        }

        // Phase 6: Restart with pglogical
        self.process.pg_ctl_stop().await?;
        self.process.pg_ctl_start(None).await?;
        self.wait_for_connection(&databases[0]).await?;

        // Phase 7: Initialize pglogical on subscriber
        for (db, slot_name) in databases.iter().zip(slot_names.iter()) {
            let subscriber = SubscriberManager::connect(&self.cli.subscriber_dsn, db).await?;

            info!("Creating pglogical extension for database {}...", db);
            subscriber.ensure_extension().await?;

            debug!("Creating replication origin for database {}...", db);
            subscriber.initialize_origin(slot_name, &remote_lsn).await?;

            info!("Creating subscriber {} for database {}...", self.cli.subscriber_name, db);
            subscriber
                .create_subscription(
                    &self.cli.subscriber_name,
                    &self.cli.subscriber_dsn,
                    &self.cli.provider_dsn,
                    &self.cli.replication_sets,
                    self.cli.apply_delay,
                    self.cli.force_text_transfer,
                )
                .await?;
        }

        // Phase 8: Optionally stop
        if self.cli.stop {
            info!("Stopping subscriber node...");
            self.process.pg_ctl_stop().await?;
        }

        info!("All done");
        Ok(())
    }

    async fn validate_or_create_data_dir(&self, expected_sysid: &str) -> Result<()> {
        if self.data_dir_exists() {
            let actual_sysid = self.read_sysid()?;
            if actual_sysid != expected_sysid {
                return Err(CreateSubscriberError::SysidMismatch {
                    expected: expected_sysid.to_string(),
                    actual: actual_sysid,
                });
            }
        }
        Ok(())
    }

    async fn run_basebackup(&self, db: &str) -> Result<()> {
        info!("Creating base backup of the remote node...");
        self.process
            .pg_basebackup(
                &self.cli.provider_dsn,
                db,
                self.cli.extra_basebackup_args.as_deref(),
            )
            .await
    }

    async fn configure_recovery(&self, restore_point: &str) -> Result<()> {
        let writer = RecoveryConfigWriter::new(&self.cli.data_dir);

        if let Some(ref recovery_conf) = self.cli.recovery_conf {
            writer.copy_from(recovery_conf)?;
        }

        writer.write_recovery_target(restore_point, &self.cli.provider_dsn)?;

        if let Some(ref pg_conf) = self.cli.postgresql_conf {
            writer.copy_postgresql_conf(pg_conf)?;
        }

        if let Some(ref hba_conf) = self.cli.pg_hba_conf {
            writer.copy_pg_hba_conf(hba_conf)?;
        }

        Ok(())
    }

    async fn start_recovery(&self) -> Result<()> {
        info!("Bringing subscriber node to the restore point...");
        self.process
            .pg_ctl_start(Some("-c shared_preload_libraries=''"))
            .await
    }

    async fn wait_for_recovery(&self, db: &str) -> Result<()> {
        self.wait_for_connection(db).await?;
        self.wait_for_primary(db).await
    }

    async fn wait_for_connection(&self, db: &str) -> Result<()> {
        debug!("Waiting for PostgreSQL to accept connections...");
        let connstr = ConnectionString::parse(&self.cli.subscriber_dsn)?
            .with_dbname(db)
            .build();

        let timeout = std::time::Duration::from_secs(300);
        let start = std::time::Instant::now();

        loop {
            if start.elapsed() > timeout {
                return Err(CreateSubscriberError::Timeout {
                    action: "accept connections".into(),
                    seconds: timeout.as_secs(),
                });
            }

            match tokio_postgres::connect(&connstr, tokio_postgres::NoTls).await {
                Ok(_) => return Ok(()),
                Err(_) => tokio::time::sleep(std::time::Duration::from_secs(1)).await,
            }
        }
    }

    async fn wait_for_primary(&self, db: &str) -> Result<()> {
        debug!("Waiting for PostgreSQL to exit recovery...");
        let connstr = ConnectionString::parse(&self.cli.subscriber_dsn)?
            .with_dbname(db)
            .build();

        let timeout = std::time::Duration::from_secs(3600); // 1 hour for large DBs
        let start = std::time::Instant::now();

        loop {
            if start.elapsed() > timeout {
                return Err(CreateSubscriberError::Timeout {
                    action: "exit recovery".into(),
                    seconds: timeout.as_secs(),
                });
            }

            let (client, connection) =
                tokio_postgres::connect(&connstr, tokio_postgres::NoTls).await?;
            tokio::spawn(connection);

            let row = client.query_one("SELECT pg_is_in_recovery()", &[]).await?;
            let in_recovery: bool = row.get(0);

            if !in_recovery {
                return Ok(());
            }

            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        }
    }

    fn data_dir_exists(&self) -> bool {
        self.cli.data_dir.join("PG_VERSION").exists()
    }

    fn read_sysid(&self) -> Result<String> {
        crate::postgres::control_file::read_sysid(&self.cli.data_dir)
    }

    fn generate_restore_point_name() -> String {
        use std::time::{SystemTime, UNIX_EPOCH};
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis();
        format!("pglogical_create_subscriber_{:x}", ts)
    }
}
```

#### `src/provider.rs`

```rust
use crate::error::{CreateSubscriberError, Result};
use tokio_postgres::{Client, NoTls};
use tracing::debug;

#[derive(Debug, Clone)]
pub struct RemoteInfo {
    pub node_id: u32,
    pub node_name: String,
    pub sysid: String,
    pub dbname: String,
    pub replication_sets: Vec<String>,
}

pub struct ProviderManager {
    client: Client,
    dbname: String,
}

impl ProviderManager {
    pub async fn connect(dsn: &str, dbname: &str) -> Result<Self> {
        let connstr = ConnectionString::parse(dsn)?.with_dbname(dbname).build();
        let (client, connection) = tokio_postgres::connect(&connstr, NoTls)
            .await
            .map_err(CreateSubscriberError::ProviderConnection)?;

        tokio::spawn(connection);

        Ok(Self {
            client,
            dbname: dbname.to_string(),
        })
    }

    pub async fn get_remote_info(&self) -> Result<RemoteInfo> {
        // Check extension exists
        let row = self
            .client
            .query_opt(
                "SELECT 1 FROM pg_extension WHERE extname = 'pglogical'",
                &[],
            )
            .await?;

        if row.is_none() {
            return Err(CreateSubscriberError::ProviderNotConfigured);
        }

        // Get node info
        let row = self
            .client
            .query_one(
                "SELECT node_id, node_name, sysid, dbname, replication_sets
                 FROM pglogical.pglogical_node_info()",
                &[],
            )
            .await?;

        Ok(RemoteInfo {
            node_id: row.get::<_, i64>(0) as u32,
            node_name: row.get(1),
            sysid: row.get(2),
            dbname: row.get(3),
            replication_sets: row
                .get::<_, String>(4)
                .split(',')
                .map(|s| s.trim().to_string())
                .collect(),
        })
    }

    pub async fn create_replication_slot(
        &self,
        subscriber_name: &str,
        drop_if_exists: bool,
    ) -> Result<String> {
        // Generate slot name
        let row = self
            .client
            .query_one(
                "SELECT pglogical.pglogical_gen_slot_name($1, $2, $3)",
                &[&self.dbname, &self.node_name().await?, &subscriber_name],
            )
            .await?;
        let slot_name: String = row.get(0);

        // Check if slot exists
        let existing = self
            .client
            .query_opt(
                "SELECT 1 FROM pg_replication_slots WHERE slot_name = $1",
                &[&slot_name],
            )
            .await?;

        if existing.is_some() {
            if drop_if_exists {
                debug!("Dropping existing slot {}...", slot_name);
                self.client
                    .execute(
                        "SELECT pg_drop_replication_slot($1)",
                        &[&slot_name],
                    )
                    .await?;
            } else {
                return Err(CreateSubscriberError::SlotExists(slot_name));
            }
        }

        // Create slot
        self.client
            .execute(
                "SELECT pg_create_logical_replication_slot($1, 'pglogical_output')",
                &[&slot_name],
            )
            .await?;

        Ok(slot_name)
    }

    pub async fn create_restore_point(&self, name: &str) -> Result<String> {
        let row = self
            .client
            .query_one("SELECT pg_create_restore_point($1)", &[&name])
            .await?;
        Ok(row.get(0))
    }

    async fn node_name(&self) -> Result<String> {
        let row = self
            .client
            .query_one("SELECT node_name FROM pglogical.pglogical_node_info()", &[])
            .await?;
        Ok(row.get(0))
    }
}
```

#### `src/process.rs`

```rust
use crate::error::{CreateSubscriberError, Result};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use tokio::process::Command;
use tracing::{debug, info};
use which::which;

pub struct ProcessRunner {
    data_dir: PathBuf,
    pg_ctl: PathBuf,
    pg_basebackup: PathBuf,
}

impl ProcessRunner {
    pub fn new(data_dir: &Path) -> Self {
        Self {
            data_dir: data_dir.to_path_buf(),
            pg_ctl: Self::find_binary("pg_ctl"),
            pg_basebackup: Self::find_binary("pg_basebackup"),
        }
    }

    fn find_binary(name: &str) -> PathBuf {
        which(name).unwrap_or_else(|_| PathBuf::from(name))
    }

    pub async fn pg_ctl_start(&self, extra_options: Option<&str>) -> Result<()> {
        let mut cmd = Command::new(&self.pg_ctl);
        cmd.arg("start")
            .arg("-D")
            .arg(&self.data_dir)
            .arg("-l")
            .arg("pglogical_create_subscriber_postgres.log")
            .arg("-w"); // Wait for startup

        if let Some(opts) = extra_options {
            cmd.arg("-o").arg(opts);
        }

        debug!("Running: {:?}", cmd);

        let output = cmd.output().await?;

        if !output.status.success() {
            return Err(CreateSubscriberError::PgCtlFailed {
                action: "start".into(),
                code: output.status.code().unwrap_or(-1),
                stderr: String::from_utf8_lossy(&output.stderr).into(),
            });
        }

        Ok(())
    }

    pub async fn pg_ctl_stop(&self) -> Result<()> {
        let output = Command::new(&self.pg_ctl)
            .arg("stop")
            .arg("-D")
            .arg(&self.data_dir)
            .arg("-m")
            .arg("fast")
            .arg("-w")
            .output()
            .await?;

        if !output.status.success() {
            return Err(CreateSubscriberError::PgCtlFailed {
                action: "stop".into(),
                code: output.status.code().unwrap_or(-1),
                stderr: String::from_utf8_lossy(&output.stderr).into(),
            });
        }

        Ok(())
    }

    pub async fn pg_basebackup(
        &self,
        provider_dsn: &str,
        dbname: &str,
        extra_args: Option<&str>,
    ) -> Result<()> {
        let connstr = format!("{} dbname={}", provider_dsn, dbname);

        let mut cmd = Command::new(&self.pg_basebackup);
        cmd.arg("-D")
            .arg(&self.data_dir)
            .arg("-d")
            .arg(&connstr)
            .arg("-X")
            .arg("stream")
            .arg("-P"); // Progress

        if let Some(args) = extra_args {
            for arg in args.split_whitespace() {
                cmd.arg(arg);
            }
        }

        info!("Running pg_basebackup...");
        debug!("Command: {:?}", cmd);

        let output = cmd.output().await?;

        if !output.status.success() {
            return Err(CreateSubscriberError::BasebackupFailed {
                code: output.status.code().unwrap_or(-1),
                stderr: String::from_utf8_lossy(&output.stderr).into(),
            });
        }

        Ok(())
    }
}
```

#### `src/main.rs`

```rust
mod cli;
mod config;
mod error;
mod orchestrator;
mod postgres;
mod process;
mod provider;
mod recovery;
mod subscriber;

use clap::Parser;
use cli::Cli;
use orchestrator::Orchestrator;
use tracing_subscriber::{fmt, EnvFilter};

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    // Initialize logging based on verbosity
    let filter = match cli.verbose {
        0 => "warn",
        1 => "info",
        2 => "debug",
        _ => "trace",
    };

    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::new(filter))
        .with_target(false)
        .init();

    let orchestrator = Orchestrator::new(cli);

    if let Err(e) = orchestrator.run().await {
        eprintln!("Error: {}", e);

        // Print cause chain
        let mut source = e.source();
        while let Some(cause) = source {
            eprintln!("Caused by: {}", cause);
            source = cause.source();
        }

        std::process::exit(1);
    }
}
```

### Testing Strategy

#### Unit Tests

```rust
// tests/unit/connstring.rs
#[cfg(test)]
mod tests {
    use crate::postgres::connstring::ConnectionString;

    #[test]
    fn parse_simple_connstring() {
        let cs = ConnectionString::parse("host=localhost port=5432 dbname=test").unwrap();
        assert_eq!(cs.host(), Some("localhost"));
        assert_eq!(cs.port(), Some(5432));
        assert_eq!(cs.dbname(), Some("test"));
    }

    #[test]
    fn parse_uri_connstring() {
        let cs = ConnectionString::parse("postgresql://user:pass@localhost:5432/mydb").unwrap();
        assert_eq!(cs.user(), Some("user"));
        assert_eq!(cs.dbname(), Some("mydb"));
    }

    #[test]
    fn build_with_override() {
        let cs = ConnectionString::parse("host=localhost dbname=orig").unwrap();
        let new_cs = cs.with_dbname("newdb").build();
        assert!(new_cs.contains("dbname=newdb"));
    }
}
```

#### Integration Tests

```rust
// tests/integration/full_workflow.rs
use assert_cmd::Command;
use predicates::prelude::*;
use tempfile::tempdir;

#[test]
fn test_missing_required_args() {
    let mut cmd = Command::cargo_bin("pglogical-create-subscriber").unwrap();
    cmd.assert()
        .failure()
        .stderr(predicate::str::contains("--pgdata"));
}

#[test]
fn test_invalid_provider_dsn() {
    let temp = tempdir().unwrap();
    let mut cmd = Command::cargo_bin("pglogical-create-subscriber").unwrap();
    cmd.args([
        "-D", temp.path().to_str().unwrap(),
        "-n", "test_sub",
        "--provider-dsn", "invalid",
        "--subscriber-dsn", "invalid",
    ])
    .assert()
    .failure();
}

// Full integration test requires running PostgreSQL instances
#[test]
#[ignore = "requires PostgreSQL"]
fn test_full_workflow() {
    // Setup provider with pglogical
    // Run subscriber creation
    // Verify replication works
}
```

## Build Integration

### CMakeLists.txt Addition

```cmake
# Optional Rust CLI build
find_program(CARGO cargo)
if(CARGO)
    set(RUST_CLI_DIR "${CMAKE_SOURCE_DIR}/pglogical-cli")

    add_custom_target(rust-cli
        COMMAND ${CARGO} build --release
        WORKING_DIRECTORY ${RUST_CLI_DIR}
        COMMENT "Building Rust CLI tools"
    )

    add_custom_target(rust-cli-install
        COMMAND ${CARGO} build --release
        COMMAND ${CMAKE_COMMAND} -E copy
            ${RUST_CLI_DIR}/target/release/pglogical-create-subscriber${CMAKE_EXECUTABLE_SUFFIX}
            ${PG_BINDIR}/pglogical_create_subscriber${CMAKE_EXECUTABLE_SUFFIX}
        WORKING_DIRECTORY ${RUST_CLI_DIR}
        COMMENT "Installing Rust CLI tools"
    )
endif()
```

### Makefile Addition

```makefile
# Rust CLI (optional, alongside C version)
RUST_CLI_DIR = pglogical-cli

.PHONY: rust-cli rust-cli-install rust-cli-clean

rust-cli:
	cd $(RUST_CLI_DIR) && cargo build --release

rust-cli-install: rust-cli
	cp $(RUST_CLI_DIR)/target/release/pglogical-create-subscriber $(bindir)/pglogical_create_subscriber_rs

rust-cli-clean:
	cd $(RUST_CLI_DIR) && cargo clean
```

## Migration Strategy

### Phase 1: Parallel Deployment (v2.6.0)

- Ship both C and Rust versions
- Rust version named `pglogical_create_subscriber_rs`
- Document as experimental/preview
- Gather feedback

### Phase 2: Feature Parity Validation (v2.7.0)

- Run both versions in CI
- Compare outputs for identical scenarios
- Fix any behavioral differences
- Add `--use-rust` flag to C version that execs Rust version

### Phase 3: Default Switch (v2.8.0)

- Rust version becomes default
- C version available via `--use-legacy` or renamed
- Deprecation notice for C version

### Phase 4: C Removal (v3.0.0)

- Remove C implementation
- Rust version is the only option

## Compatibility

### Command-Line Compatibility

The Rust version will accept all existing arguments:

```bash
# These should work identically
pglogical_create_subscriber \
    -D /var/lib/pgsql/subscriber \
    -n subscriber1 \
    --provider-dsn "host=provider port=5432 dbname=mydb" \
    --subscriber-dsn "host=localhost port=5433 dbname=mydb" \
    --replication-sets "default,ddl_sql" \
    -v

pglogical_create_subscriber_rs \
    -D /var/lib/pgsql/subscriber \
    -n subscriber1 \
    --provider-dsn "host=provider port=5432 dbname=mydb" \
    --subscriber-dsn "host=localhost port=5433 dbname=mydb" \
    --replication-sets "default,ddl_sql" \
    -v
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Connection error |
| 3 | Configuration error |
| 4 | Timeout |

## Advantages Over C Implementation

| Aspect | C | Rust |
|--------|---|------|
| Error messages | Generic `die()` | Typed errors with context |
| Memory safety | Manual | Automatic |
| Async I/O | Manual polling | tokio runtime |
| Cross-platform | `#ifdef` | Native |
| Testing | Difficult | cargo test |
| Dependencies | PostgreSQL headers | Cargo crates |
| Build | Requires PG dev | Standalone |

## File Summary

| File | Description |
|------|-------------|
| `pglogical-cli/Cargo.toml` | Rust project configuration |
| `pglogical-cli/src/main.rs` | Entry point |
| `pglogical-cli/src/cli.rs` | CLI argument parsing |
| `pglogical-cli/src/error.rs` | Error types |
| `pglogical-cli/src/orchestrator.rs` | Main workflow |
| `pglogical-cli/src/provider.rs` | Provider operations |
| `pglogical-cli/src/subscriber.rs` | Subscriber operations |
| `pglogical-cli/src/process.rs` | External process runner |
| `pglogical-cli/src/postgres/*.rs` | PostgreSQL utilities |
| `pglogical-cli/src/recovery/*.rs` | Recovery config writer |

## Future Work

1. **Progress reporting** - Real-time status during basebackup
2. **Resume capability** - Continue from failed state
3. **Dry-run mode** - Show what would happen without executing
4. **JSON output** - Machine-readable progress/status
5. **Parallel slot creation** - Create slots concurrently for multi-DB
6. **SSH tunneling** - Built-in SSH tunnel support
