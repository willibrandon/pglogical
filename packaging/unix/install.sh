#!/bin/bash
#
# pglogical Installation Script for Linux and macOS
#
# Usage:
#   ./install.sh                              # Use pg_config from PATH
#   PG_CONFIG=/path/to/pg_config ./install.sh # Use specific pg_config
#   PGDIR=/path/to/postgresql ./install.sh    # Use specific PostgreSQL directory
#
# Environment Variables:
#   PG_CONFIG - Path to pg_config executable
#   PGDIR     - PostgreSQL installation directory (alternative to pg_config)
#
# This script installs pglogical extension files to the PostgreSQL directories
# determined by pg_config or PGDIR. It will use sudo if the target directories
# require elevated permissions.

set -e

# Colors for output (if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

# Print colored message
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Determine script directory (where package files are located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine PostgreSQL directories
if [ -n "$PGDIR" ]; then
    # User specified PostgreSQL directory directly
    if [ ! -d "$PGDIR" ]; then
        error "PGDIR directory does not exist: $PGDIR"
        exit 1
    fi
    info "Using PostgreSQL directory from PGDIR: $PGDIR"

    # Determine paths based on PGDIR
    BINDIR="${PGDIR}/bin"
    PKGLIBDIR="${PGDIR}/lib"
    SHAREDIR="${PGDIR}/share"
    EXTENSIONDIR="${SHAREDIR}/extension"

    # Try to get version from pg_config if available in PGDIR
    if [ -x "${PGDIR}/bin/pg_config" ]; then
        PG_VERSION=$("${PGDIR}/bin/pg_config" --version 2>/dev/null || echo "Unknown")
    else
        PG_VERSION="Unknown (PGDIR mode)"
    fi

elif [ -n "$PG_CONFIG" ]; then
    # User specified pg_config path
    if [ ! -x "$PG_CONFIG" ]; then
        error "PG_CONFIG is set but not executable: $PG_CONFIG"
        exit 1
    fi
    info "Using pg_config from PG_CONFIG: $PG_CONFIG"

    BINDIR=$("$PG_CONFIG" --bindir)
    PKGLIBDIR=$("$PG_CONFIG" --pkglibdir)
    SHAREDIR=$("$PG_CONFIG" --sharedir)
    EXTENSIONDIR="${SHAREDIR}/extension"
    PG_VERSION=$("$PG_CONFIG" --version)

elif command -v pg_config >/dev/null 2>&1; then
    # Use pg_config from PATH
    PG_CONFIG="pg_config"
    info "Using pg_config from PATH: $(which pg_config)"

    BINDIR=$("$PG_CONFIG" --bindir)
    PKGLIBDIR=$("$PG_CONFIG" --pkglibdir)
    SHAREDIR=$("$PG_CONFIG" --sharedir)
    EXTENSIONDIR="${SHAREDIR}/extension"
    PG_VERSION=$("$PG_CONFIG" --version)

else
    error "Cannot determine PostgreSQL location"
    echo ""
    echo "Please use one of the following options:"
    echo ""
    echo "  1. Add PostgreSQL bin directory to PATH:"
    echo "     export PATH=/usr/lib/postgresql/17/bin:\$PATH"
    echo "     ./install.sh"
    echo ""
    echo "  2. Set PG_CONFIG environment variable:"
    echo "     PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config ./install.sh"
    echo ""
    echo "  3. Set PGDIR to PostgreSQL installation directory:"
    echo "     PGDIR=/usr/lib/postgresql/17 ./install.sh"
    echo ""
    exit 1
fi

info "PostgreSQL version: $PG_VERSION"
info "Binary directory: $BINDIR"
info "Library directory: $PKGLIBDIR"
info "Extension directory: $EXTENSIONDIR"

# Check if directories exist
if [ ! -d "$PKGLIBDIR" ]; then
    error "Library directory does not exist: $PKGLIBDIR"
    exit 1
fi

if [ ! -d "$EXTENSIONDIR" ]; then
    warn "Extension directory does not exist: $EXTENSIONDIR"
    echo "Creating extension directory..."
    if [ -w "$(dirname "$EXTENSIONDIR")" ]; then
        mkdir -p "$EXTENSIONDIR"
    else
        sudo mkdir -p "$EXTENSIONDIR"
    fi
fi

# Determine if we need sudo
NEED_SUDO=false
if [ ! -w "$BINDIR" ] || [ ! -w "$PKGLIBDIR" ] || [ ! -w "$EXTENSIONDIR" ]; then
    NEED_SUDO=true
    warn "Target directories require elevated permissions, using sudo"
fi

# Copy function that uses sudo if needed
copy_file() {
    local src="$1"
    local dst="$2"
    local mode="${3:-644}"

    if [ ! -f "$src" ]; then
        error "Source file not found: $src"
        return 1
    fi

    if $NEED_SUDO; then
        sudo install -m "$mode" "$src" "$dst"
    else
        install -m "$mode" "$src" "$dst"
    fi
}

# Install executables (if bin directory exists in package)
if [ -d "$SCRIPT_DIR/bin" ]; then
    info "Installing executables..."

    # Check if bin directory exists on target, create if needed
    if [ ! -d "$BINDIR" ]; then
        warn "Binary directory does not exist: $BINDIR"
        echo "Creating binary directory..."
        if [ -w "$(dirname "$BINDIR")" ]; then
            mkdir -p "$BINDIR"
        else
            sudo mkdir -p "$BINDIR"
        fi
    fi

    # Install each executable
    for exe in "$SCRIPT_DIR"/bin/*; do
        if [ -f "$exe" ]; then
            filename=$(basename "$exe")
            copy_file "$exe" "$BINDIR/$filename" 755
            echo "  Installed: $filename"
        fi
    done
fi

# Install shared libraries
info "Installing shared libraries..."
for lib in "$SCRIPT_DIR"/lib/*.so "$SCRIPT_DIR"/lib/*.dylib; do
    if [ -f "$lib" ]; then
        filename=$(basename "$lib")
        copy_file "$lib" "$PKGLIBDIR/$filename" 755
        echo "  Installed: $filename"
    fi
done

# Install extension files
info "Installing extension files..."
for ext in "$SCRIPT_DIR"/share/extension/*; do
    if [ -f "$ext" ]; then
        filename=$(basename "$ext")
        copy_file "$ext" "$EXTENSIONDIR/$filename" 644
        echo "  Installed: $filename"
    fi
done

echo ""
info "Installation complete!"
echo ""
echo "To enable pglogical in your database, run:"
echo "  CREATE EXTENSION pglogical;"
echo ""
echo "For more information, see: https://github.com/2ndQuadrant/pglogical"
