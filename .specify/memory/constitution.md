<!--
SYNC IMPACT REPORT
==================
Version change: 1.1.0 → 1.2.0 (MINOR - materially expanded testing requirements)

Modified principles:
- III. Testing Discipline: Strengthened from SHOULD to MUST requirements; added explicit mandate for full conflict tests regardless of complexity

Added sections: None

Removed sections: None

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

All changes MUST be validated through the project's regression test framework. Test complexity is NOT a valid reason to skip or simplify tests.

- Bug fixes MUST include a regression test demonstrating the fix
- New features MUST include tests covering primary use cases and edge conditions
- Tests MUST pass on the target PostgreSQL versions before merge
- Integration tests MUST verify actual replication between provider and subscriber nodes
- Conflict-related features MUST include full conflict scenario tests with actual provider/subscriber setup
- Test complexity is NEVER an excuse to defer, simplify, or skip testing
- Tests MUST exercise the complete code path, not just schema or configuration validation
- If a test requires complex setup (multi-node replication, conflict scenarios), that setup MUST be implemented

**Rationale**: Logical replication involves complex state management across distributed systems. Untested changes risk subtle data corruption or replication breakage. Simplified tests that skip actual replication verification provide false confidence and hide bugs.

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

### VI. Implementation Completeness

All implementations MUST be complete and fully functional. Deferred work, placeholder implementations, and stub functions are strictly prohibited.

- Tasks MUST be implemented in full; partial implementations are NOT acceptable
- Code containing `TODO`, `FIXME`, or placeholder comments indicating deferred work MUST NOT be committed
- Stub functions that return dummy values or skip actual implementation logic are FORBIDDEN
- Each task MUST deliver working, tested functionality before being marked complete
- Simplifying or "placeholder-ing" implementations to defer actual work violates this principle
- If a task cannot be fully implemented, it MUST be split into smaller completable units or blocked with explicit justification

**Rationale**: Deferred implementations create technical debt, obscure actual project status, and lead to incomplete features reaching production. A task is either fully done or not done at all.

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

**Version**: 1.2.0 | **Ratified**: 2025-12-25 | **Last Amended**: 2025-12-25
