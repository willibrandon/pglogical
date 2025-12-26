<!--
SYNC IMPACT REPORT
==================
Version change: N/A → 1.0.0 (initial ratification)

Modified principles: None (initial creation)

Added sections:
- Core Principles (5 principles)
  - I. PostgreSQL Version Compatibility
  - II. Backward Compatibility
  - III. Testing Discipline
  - IV. Code Quality & Memory Safety
  - V. Replication Integrity
- C Extension Standards
- Development Workflow
- Governance

Removed sections: None (initial creation)

Templates requiring updates:
- .specify/templates/plan-template.md: ✅ No updates needed (Constitution Check section already generic)
- .specify/templates/spec-template.md: ✅ No updates needed (requirements format compatible)
- .specify/templates/tasks-template.md: ✅ No updates needed (task structure compatible)
- .specify/templates/commands/*.md: N/A (no command files exist)

Follow-up TODOs: None
-->

# pglogical Constitution

## Core Principles

### I. PostgreSQL Version Compatibility

All code MUST compile and function correctly across supported PostgreSQL versions (currently 9.4 through 18+).

- Version-specific code MUST use appropriate `#if PG_VERSION_NUM` guards
- New features SHOULD be backported when technically feasible
- Deprecation of PostgreSQL version support requires a major release and advance notice
- Changes affecting version compatibility MUST document which versions are impacted

**Rationale**: pglogical's value lies in enabling replication across PostgreSQL versions and environments. Breaking version support undermines the core use case.

### II. Backward Compatibility

Extension upgrades MUST NOT break existing replication setups or require manual intervention beyond `ALTER EXTENSION pglogical UPDATE`.

- Schema migrations MUST be forward-compatible
- API function signatures MUST remain stable within major versions
- Configuration parameter changes MUST provide sensible defaults preserving prior behavior
- Replication protocol changes MUST maintain compatibility with prior subscriber versions where possible

**Rationale**: Production replication clusters cannot tolerate surprise breakage during upgrades. Users depend on seamless rolling upgrades.

### III. Testing Discipline

All changes SHOULD be validated through the project's regression test framework.

- Bug fixes SHOULD include a regression test demonstrating the fix
- New features SHOULD include tests covering primary use cases and edge conditions
- Tests MUST pass on the target PostgreSQL versions before merge
- Integration tests SHOULD verify actual replication between provider and subscriber nodes

**Rationale**: Logical replication involves complex state management across distributed systems. Untested changes risk subtle data corruption or replication breakage.

### IV. Code Quality & Memory Safety

C code MUST follow PostgreSQL extension development best practices.

- Memory allocations MUST use PostgreSQL memory contexts appropriately
- Error handling MUST use PostgreSQL's `ereport`/`elog` mechanisms
- Catalog access MUST use proper locking and cache invalidation
- SPI usage MUST handle errors and restore state correctly
- Code MUST compile without warnings on supported compilers with `-Wall`

**Rationale**: PostgreSQL extensions run in the database server process. Memory leaks, crashes, or corruption affect all database operations, not just replication.

### V. Replication Integrity

Changes affecting the replication data path MUST preserve data consistency guarantees.

- Row filtering and column selection MUST be applied consistently on provider and subscriber
- Conflict resolution MUST produce deterministic, documented outcomes
- Sequence synchronization MUST prevent duplicate value generation
- Transaction boundaries MUST be preserved during apply

**Rationale**: Users trust pglogical to replicate data accurately. Silent data divergence between nodes is the worst possible failure mode.

## C Extension Standards

Technical constraints specific to PostgreSQL C extension development:

- All exported functions MUST use `PG_FUNCTION_INFO_V1` macro
- Background workers MUST handle shutdown signals gracefully
- Shared memory usage MUST be properly sized and initialized
- Replication slots MUST be created and dropped cleanly
- WAL decoding callbacks MUST handle all message types or explicitly skip unknown types
- Output plugins MUST produce valid protocol messages

## Development Workflow

Guidelines for contributing to pglogical:

- Feature branches SHOULD follow the pattern `###-feature-name` where `###` is an issue number
- Commits SHOULD be atomic and include meaningful messages
- Pull requests SHOULD reference related issues
- Documentation updates SHOULD accompany user-visible changes
- Breaking changes MUST be documented in release notes

## Governance

This constitution establishes non-negotiable principles for pglogical development.

**Amendment Process**:
1. Proposed changes MUST be documented with rationale
2. Changes affecting core principles require maintainer consensus
3. All amendments MUST update the version and last-amended date

**Versioning Policy**:
- MAJOR: Removal or redefinition of core principles
- MINOR: New principles or significant expansions
- PATCH: Clarifications and wording improvements

**Compliance**:
- All pull requests SHOULD be reviewed against these principles
- Violations of MUST requirements block merge
- Violations of SHOULD requirements require documented justification

**Version**: 1.0.0 | **Ratified**: 2025-12-25 | **Last Amended**: 2025-12-25
