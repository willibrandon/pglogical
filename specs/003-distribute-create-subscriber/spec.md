# Feature Specification: Distribute pglogical_create_subscriber

**Feature Branch**: `003-distribute-create-subscriber`
**Created**: 2026-01-08
**Status**: Draft
**Target Version**: pglogical 2.5.1
**Input**: User description: "Include the pglogical_create_subscriber executable in all release packages"

## Overview

The `pglogical_create_subscriber` utility is a command-line tool that creates a new pglogical subscriber from a physical base backup. This enables fast subscriber setup for large databases by combining physical backup with logical replication.

Currently, this utility is built during the normal build process but is not included in any release packages (Windows MSI/ZIP, Linux tar.gz, macOS tar.gz). Users who need this tool must build pglogical from source, which creates an unnecessary barrier to adoption.

This feature ensures the utility is distributed in all release packages alongside the extension libraries.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Windows MSI Installation (Priority: P1)

A database administrator installs pglogical on Windows using the MSI installer. After installation, they can immediately use the `pglogical_create_subscriber` utility from the PostgreSQL bin directory without any additional steps.

**Why this priority**: MSI is the primary distribution method for Windows users and provides the most seamless installation experience. Most Windows users expect all components to be available after running the installer.

**Independent Test**: Can be fully tested by installing the MSI package and running `pglogical_create_subscriber --help` from the command line.

**Acceptance Scenarios**:

1. **Given** a Windows system with PostgreSQL installed, **When** the user installs the pglogical MSI package, **Then** the `pglogical_create_subscriber.exe` utility is installed to the PostgreSQL bin directory.
2. **Given** a completed MSI installation, **When** the user runs `pglogical_create_subscriber --help`, **Then** the utility displays its help message and available options.

---

### User Story 2 - Linux tar.gz Installation (Priority: P1)

A system administrator downloads the Linux tar.gz package and uses the provided install script. After installation, the `pglogical_create_subscriber` utility is available in the PostgreSQL bin directory alongside other PostgreSQL tools.

**Why this priority**: Linux is the most common production deployment platform for PostgreSQL. Having the utility available through the standard package ensures consistency with the overall PostgreSQL toolset.

**Independent Test**: Can be fully tested by extracting the tar.gz, running the install script, and executing `pglogical_create_subscriber --help`.

**Acceptance Scenarios**:

1. **Given** a Linux system with PostgreSQL installed, **When** the user extracts the tar.gz and runs the install script, **Then** the `pglogical_create_subscriber` utility is installed to the PostgreSQL bin directory.
2. **Given** a completed installation, **When** the user runs `pglogical_create_subscriber --help`, **Then** the utility displays its help message.

---

### User Story 3 - macOS tar.gz Installation (Priority: P1)

A developer downloads the macOS tar.gz package for their ARM64 Mac. After running the install script, they can use `pglogical_create_subscriber` to quickly set up a subscriber node for development.

**Why this priority**: macOS is commonly used for development and testing environments. Developers need quick access to all pglogical tools.

**Independent Test**: Can be fully tested by extracting the tar.gz, running the install script, and verifying the utility works.

**Acceptance Scenarios**:

1. **Given** a macOS system with PostgreSQL installed, **When** the user extracts the tar.gz and runs the install script, **Then** the `pglogical_create_subscriber` utility is installed to the PostgreSQL bin directory.
2. **Given** a completed installation, **When** the user runs `pglogical_create_subscriber --help`, **Then** the utility displays its help message.

---

### User Story 4 - Windows ZIP Manual Installation (Priority: P2)

An advanced user who prefers manual installation downloads the Windows ZIP package. The package contains the utility in a bin directory, allowing them to manually copy files to their desired locations.

**Why this priority**: ZIP packages are a secondary distribution method for users who prefer manual control over installation.

**Independent Test**: Can be fully tested by extracting the ZIP and verifying the bin directory contains the executable.

**Acceptance Scenarios**:

1. **Given** a downloaded Windows ZIP package, **When** the user extracts the archive, **Then** the `pglogical_create_subscriber.exe` is present in the bin subdirectory.
2. **Given** the extracted ZIP contents, **When** the user copies the bin directory contents to PostgreSQL's bin directory, **Then** the utility is usable from the command line.

---

### Edge Cases

- What happens when the target bin directory doesn't exist? The install script should create it or report a clear error.
- What happens when the user doesn't have write permissions to the bin directory? The install script should prompt for elevated permissions or provide clear instructions.
- What happens when upgrading from a version without the utility to one with it? The new utility should be installed without affecting existing files.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Release packages MUST include the `pglogical_create_subscriber` executable for all supported platforms (Windows, Linux, macOS).
- **FR-002**: Windows MSI packages MUST install the executable to the PostgreSQL bin directory during standard installation.
- **FR-003**: Windows ZIP packages MUST include the executable in a bin subdirectory within the archive.
- **FR-004**: Linux tar.gz packages MUST include the executable in a bin subdirectory within the archive.
- **FR-005**: macOS tar.gz packages MUST include the executable in a bin subdirectory within the archive.
- **FR-006**: The Unix install script MUST install executables from the bin directory to the PostgreSQL bin directory.
- **FR-007**: Package documentation MUST mention the bundled utility and its purpose.
- **FR-008**: The installed utility MUST be functional immediately after installation (no additional setup required).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of release packages (Windows MSI, Windows ZIP, Linux tar.gz, macOS tar.gz) include the `pglogical_create_subscriber` utility.
- **SC-002**: Users can run `pglogical_create_subscriber --help` successfully within 1 minute of completing installation.
- **SC-003**: All release package documentation mentions the included utility.
- **SC-004**: Zero additional manual steps required to use the utility after standard package installation.

## Assumptions

- The `pglogical_create_subscriber` utility builds successfully on all supported platforms (this is already the case).
- The utility has no runtime dependencies beyond what is already included with PostgreSQL.
- The existing test (`t/010_pglogical_create_subscriber.pl`) validates the utility's functionality.
- Users have appropriate permissions to access the PostgreSQL bin directory.

## Out of Scope

- Changes to the utility's functionality or command-line interface.
- Adding the utility to operating system package managers (apt, yum, brew).
- Auto-updating mechanisms for the utility.
- Separate versioning of the utility from the main extension.
