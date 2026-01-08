# Feature Specification: GitHub Releases Distribution

**Feature Branch**: `002-github-releases`
**Created**: 2026-01-05
**Status**: Draft
**Target**: pglogical 2.5.0

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Download Pre-built Binary for My Platform (Priority: P1)

As a pglogical user, I want to download a pre-built binary package for my specific platform and PostgreSQL version so that I can install pglogical without compiling from source.

**Why this priority**: This is the core value proposition - users need working binaries to use the extension. Without downloadable artifacts, there's no distribution to speak of.

**Independent Test**: Can be fully tested by navigating to a GitHub Release page, downloading a package for a specific platform/PostgreSQL version combination, and verifying the package contains the expected files (shared library + SQL files).

**Acceptance Scenarios**:

1. **Given** a published release v2.5.0 exists, **When** a Windows user with PostgreSQL 17 visits the release page, **Then** they can download `pglogical-2.5.0-pg17-windows-x64.zip` containing pglogical.dll, pglogical_output.dll, and extension SQL files
2. **Given** a published release v2.5.0 exists, **When** a Linux user with PostgreSQL 16 visits the release page, **Then** they can download `pglogical-2.5.0-pg16-linux-x64.tar.gz` containing pglogical.so, pglogical_output.so, and extension SQL files
3. **Given** a published release v2.5.0 exists, **When** a macOS Apple Silicon user with PostgreSQL 17 visits the release page, **Then** they can download `pglogical-2.5.0-pg17-macos-arm64.tar.gz` containing pglogical.dylib and extension SQL files
4. **Given** a published release v2.5.0 exists, **When** a macOS Intel user with PostgreSQL 15 visits the release page, **Then** they can download `pglogical-2.5.0-pg15-macos-x64.tar.gz` containing the appropriate dylib files

---

### User Story 2 - Install via Windows MSI Installer (Priority: P2)

As a Windows administrator, I want to use an MSI installer to deploy pglogical so that installation integrates with Windows standard software management practices and automatically detects my PostgreSQL installation directory.

**Why this priority**: MSI installers provide the most seamless Windows experience with automatic path detection and proper uninstall support. This significantly reduces friction for Windows users who may be less comfortable with manual file copying.

**Independent Test**: Can be fully tested by running the MSI installer on a Windows machine with PostgreSQL installed, verifying it detects the correct PostgreSQL directory, installs files to proper locations, and registers for clean uninstall.

**Acceptance Scenarios**:

1. **Given** PostgreSQL 17 is installed in the default location on Windows, **When** I run the MSI installer for pglogical-pg17, **Then** the installer automatically detects the PostgreSQL installation directory and copies files to the correct lib and share/extension directories
2. **Given** the MSI installer has been run, **When** I open Windows Add/Remove Programs, **Then** pglogical appears in the installed programs list with an uninstall option
3. **Given** the MSI installer detected a non-standard PostgreSQL path, **When** I browse to select a different directory, **Then** the installer allows me to specify the correct PostgreSQL root directory

---

### User Story 3 - Automatic Release on Git Tag (Priority: P1)

As a release manager, I want the release pipeline to automatically trigger when I push a version tag so that releases are consistent, reproducible, and require minimal manual intervention.

**Why this priority**: Automation is critical for consistency and reducing human error. Without automated triggering, every release would require manual coordination across platforms.

**Independent Test**: Can be fully tested by pushing a tag matching the pattern `v*` (e.g., `v2.5.0`) and verifying that GitHub Actions workflows start building for all platform/PostgreSQL version combinations.

**Acceptance Scenarios**:

1. **Given** I push a tag `v2.5.0` to the repository, **When** GitHub Actions processes the push event, **Then** build jobs start for all 6 PostgreSQL versions (13-18) across Windows, Linux, and macOS platforms
2. **Given** all platform builds complete successfully, **When** the release job runs, **Then** a GitHub Release is created with the tag name and all build artifacts attached
3. **Given** a tag contains a hyphen (e.g., `v2.5.0-beta1`), **When** the release is created, **Then** it is marked as a prerelease

---

### User Story 4 - Download Source Package with Dependencies (Priority: P3)

As a developer building from source, I want to download a complete source package that includes all submodule dependencies so that I can build pglogical without additional repository cloning steps.

**Why this priority**: Source packages are essential for users who need to build for unsupported platforms or with custom configurations, but binary packages serve the majority of users.

**Independent Test**: Can be fully tested by downloading the source tarball, extracting it, and running `make` without needing to initialize git submodules separately.

**Acceptance Scenarios**:

1. **Given** a release exists, **When** I download `pglogical-2.5.0-source.tar.gz`, **Then** the archive includes all submodule contents (not just submodule references)
2. **Given** I extract the source tarball, **When** I run `make` with a valid PostgreSQL installation, **Then** the build succeeds without git submodule commands

---

### User Story 5 - Verify Download Integrity (Priority: P3)

As a security-conscious user, I want SHA256 checksums for all release artifacts so that I can verify downloads haven't been corrupted or tampered with.

**Why this priority**: Security verification is important but most users rely on HTTPS download integrity. This is a best practice but not blocking for basic functionality.

**Independent Test**: Can be fully tested by downloading checksums.txt, downloading any artifact, computing its SHA256 hash locally, and comparing against the published checksum.

**Acceptance Scenarios**:

1. **Given** a release exists, **When** I download checksums.txt, **Then** it contains SHA256 hashes for every other artifact in the release
2. **Given** I download any artifact and its corresponding checksum, **When** I compute `sha256sum <file>`, **Then** the hash matches the published value

---

### User Story 6 - Install on Linux/macOS with Helper Script (Priority: P2)

As a Linux or macOS user, I want a simple installation script included in the package so that I can install the extension without memorizing PostgreSQL directory locations.

**Why this priority**: While experienced users can copy files manually, an install script significantly improves usability and reduces installation errors.

**Independent Test**: Can be fully tested by extracting the package and running `./install.sh`, then verifying files are copied to the correct PostgreSQL directories.

**Acceptance Scenarios**:

1. **Given** I extract the Linux/macOS package, **When** I run `./install.sh`, **Then** shared libraries are copied to `$(pg_config --pkglibdir)` and extension files to `$(pg_config --sharedir)/extension`
2. **Given** pg_config is not in PATH, **When** I set `PG_CONFIG=/path/to/pg_config` and run `./install.sh`, **Then** the script uses my specified pg_config
3. **Given** the target directories require root access, **When** I run `./install.sh`, **Then** the script uses sudo for copy operations and prompts for password if needed

---

### User Story 7 - CI Validation on Pull Requests (Priority: P2)

As a contributor, I want continuous integration to validate my changes build correctly on all supported platforms so that I catch issues before they reach a release.

**Why this priority**: CI prevents broken releases and gives contributors confidence their changes work. This is essential infrastructure that enables the release process.

**Independent Test**: Can be fully tested by opening a pull request with a minor change and verifying build jobs run for all platform/PostgreSQL version combinations.

**Acceptance Scenarios**:

1. **Given** I open a pull request to REL2_x_STABLE, **When** GitHub Actions processes the PR, **Then** build and test jobs run for all PostgreSQL versions (13-18) on Linux, Windows, and macOS
2. **Given** a build fails for PostgreSQL 15 on Linux, **When** I view the Actions tab, **Then** I can see which specific job failed and access its logs
3. **Given** all CI checks pass on a PR, **When** a maintainer merges the PR, **Then** the merge is allowed (branch protection enforced)

---

### Edge Cases

- What happens when a PostgreSQL version is not available via package manager (e.g., PG18 not yet in Homebrew)? Build job fails gracefully with clear error message; matrix should allow individual job failures without stopping others (fail-fast: false)
- How does the system handle PostgreSQL registry entries missing on Windows? MSI installer provides a directory browse option as fallback
- What happens if submodule clone fails during CI? Submodules use HTTPS URLs (not SSH) to avoid authentication issues in CI
- How does the system handle simultaneous tag pushes? Each tag triggers its own independent workflow run
- What if a previous release with the same version exists? MSI installer handles upgrades via MajorUpgrade element; GitHub Release action uses existing release if present

## Requirements *(mandatory)*

### Functional Requirements

#### Build Pipeline Requirements

- **FR-001**: System MUST build pglogical for PostgreSQL versions 13, 14, 15, 16, 17, and 18
- **FR-002**: System MUST build for Windows x64 using MSVC compiler via Visual Studio 2022
- **FR-003**: System MUST build for Linux x64 using GCC compiler
- **FR-004**: System MUST build for macOS ARM64 (Apple Silicon) using Clang
- **FR-005**: System MUST build for macOS x64 (Intel) using Clang
- **FR-006**: System MUST run regression tests as part of CI for all platforms (Linux, macOS, and Windows)
- **FR-007**: Build matrix MUST allow individual job failures without stopping other jobs (fail-fast: false)

#### Artifact Requirements

- **FR-008**: System MUST produce Windows artifacts as both ZIP archive and MSI installer per PostgreSQL version
- **FR-009**: System MUST produce Linux artifacts as tar.gz archive per PostgreSQL version
- **FR-010**: System MUST produce macOS artifacts as tar.gz archive per PostgreSQL version per architecture (arm64, x64)
- **FR-011**: System MUST produce source archives as both tar.gz and zip including submodule contents
- **FR-012**: Each binary package MUST include shared library files (dll/so/dylib), control file, and SQL extension files
- **FR-013**: Linux and macOS packages MUST include an install.sh helper script
- **FR-014**: Windows packages MUST include README.md with installation instructions

#### Naming Convention Requirements

- **FR-015**: Artifact file names MUST follow pattern: `pglogical-{version}-pg{pg_version}-{platform}-{arch}.{ext}`
- **FR-016**: Source archives MUST follow pattern: `pglogical-{version}-source.{ext}`
- **FR-017**: Version in artifact names MUST exclude the 'v' prefix from the git tag

#### Windows MSI Installer Requirements

- **FR-018**: MSI installer MUST auto-detect PostgreSQL installation directory from Windows registry
- **FR-019**: MSI installer MUST allow user to browse and select PostgreSQL directory if auto-detection fails
- **FR-020**: MSI installer MUST support side-by-side installation for different PostgreSQL versions (unique UpgradeCode per PG version)
- **FR-021**: MSI installer MUST support clean uninstall via Windows Add/Remove Programs
- **FR-022**: MSI installer MUST support upgrade from previous pglogical versions (same PG version)

#### GitHub Release Requirements

- **FR-023**: System MUST automatically create GitHub Release when a tag matching `v*` is pushed
- **FR-024**: System MUST attach all build artifacts to the GitHub Release
- **FR-025**: System MUST generate release notes with installation instructions for each platform (template includes: version highlights, platform-specific install commands, link to checksums.txt, upgrade notes)
- **FR-026**: System MUST generate checksums.txt containing SHA256 hashes of all artifacts
- **FR-027**: Releases for tags containing a hyphen (e.g., `-beta`, `-rc`) MUST be marked as prerelease

#### CI Requirements

- **FR-028**: CI workflow MUST run on push to REL2_x_STABLE branch and windows-build branch
- **FR-029**: CI workflow MUST run on pull requests targeting REL2_x_STABLE
- **FR-030**: CI MUST configure git to use HTTPS for submodule URLs (not SSH) to avoid authentication issues
- **FR-031**: CI MUST check out repository with submodules recursively

### Key Entities

- **Release Artifact**: A downloadable file attached to a GitHub Release (binary package, installer, or source archive); identified by filename following naming convention
- **Build Matrix**: The combination of platform (Windows/Linux/macOS), architecture (x64/arm64), and PostgreSQL version (13-18) that defines all build targets
- **GitHub Release**: A tagged release on GitHub containing release notes, checksums, and all artifacts for a specific version
- **MSI Installer**: Windows Installer package built using WiX Toolset that provides automated installation with PostgreSQL path detection

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can download and install pglogical on any supported platform in under 5 minutes (excluding download time); measured from package extraction to successful `CREATE EXTENSION pglogical`
- **SC-002**: A complete release (all 30+ artifacts) is published within 60 minutes of tag push
- **SC-003**: 100% of release artifacts pass SHA256 checksum verification
- **SC-004**: Windows MSI installer successfully detects PostgreSQL installation in 95% of standard installations (standard = default installation path with registry entries from official PostgreSQL installer or EDB installer)
- **SC-005**: Install helper scripts work without modification on standard Linux distributions (Ubuntu 20.04+, RHEL/CentOS 8+) and macOS versions (13 Ventura through 26 Tahoe) with Homebrew or standard PostgreSQL installations
- **SC-006**: CI provides build status within 30 minutes for any pull request
- **SC-007**: All 6 PostgreSQL versions build successfully for each supported platform before a release is published
- **SC-008**: Source package builds successfully when extracted and compiled with `make` (no git required after extraction)

## Assumptions

- PostgreSQL development headers are available via standard package managers (apt for Linux, Homebrew for macOS, Chocolatey for Windows)
- GitHub Actions runners provide sufficient resources for building PostgreSQL extensions
- WiX Toolset v5 is available as a .NET global tool in GitHub Actions Windows runners
- PostgreSQL versions 13-18 remain the supported range for pglogical 2.5.0
- Repository submodules use HTTPS URLs to enable CI cloning without SSH key configuration
- GitHub Actions windows-2022 runner supports Windows 10 and Windows 11 compatible builds (builds on Windows Server 2022)
- GitHub Actions macos-14 runner provides ARM64 architecture; macos-13 runner provides x64 architecture (runner names reflect image generation, not macOS version - both run current macOS releases)

## Out of Scope

- Code signing for Windows binaries (noted as future enhancement)
- macOS notarization for Gatekeeper (noted as future enhancement)
- Windows ARM64 builds (PostgreSQL doesn't officially support Windows ARM64)
- Linux ARM64 builds (can be added in future if demand exists)
- Automated testing of installed packages (manual verification for now)
- RPM or DEB package creation (users install via helper script or manual copy)
- Homebrew formula or APT repository publishing
