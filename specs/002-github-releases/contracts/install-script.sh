#!/bin/bash
# Contract: Linux/macOS Installation Script
# This contract defines the expected behavior of the install helper script.
#
# Requirements from spec:
# - FR-013: Linux and macOS packages MUST include an install.sh helper script
# - User Story 6: Install on Linux/macOS with Helper Script
#
# Expected Behavior:
# 1. Use pg_config from PATH or PG_CONFIG environment variable
# 2. Copy shared libraries to $(pg_config --pkglibdir)
# 3. Copy extension files to $(pg_config --sharedir)/extension
# 4. Use sudo if target directories require elevated permissions
# 5. Exit with clear error if pg_config not found

set -e

# Configuration (environment overrides)
# PG_CONFIG - path to pg_config if not in PATH

# Expected outputs:
# - pglogical.so/dylib copied to pkglibdir
# - pglogical_output.so/dylib copied to pkglibdir
# - pglogical.control copied to sharedir/extension
# - pglogical--*.sql files copied to sharedir/extension

# Expected error conditions:
# - pg_config not found (exit 1)
# - Copy permission denied without sudo (prompt for sudo)
# - Target directory doesn't exist (create it)

# Contract validation:
# 1. Script must be executable (chmod +x)
# 2. Script must work on bash 3.2+ (macOS default)
# 3. Script must not require external dependencies beyond coreutils

# Acceptance Scenarios (from spec):
#
# Scenario 1: ./install.sh with pg_config in PATH
# - Copies libraries to $(pg_config --pkglibdir)
# - Copies extension files to $(pg_config --sharedir)/extension
#
# Scenario 2: PG_CONFIG=/path/to/pg_config ./install.sh
# - Uses specified pg_config
#
# Scenario 3: Target directories require root
# - Uses sudo for copy operations
# - Prompts for password if needed
