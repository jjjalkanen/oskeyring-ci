# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the `test_oskeyring` repository - a Podman-based container orchestration system that demonstrates end-to-end package building, distribution, and testing across multiple Linux distributions and package formats.

## Architecture

The system consists of:
- **Builder container** (Fedora): Compiles Rust app, packages to 4 formats, orchestrates testing
- **4 Registry containers** (nginx): Serve Flatpak, Snap, Debian, and RPM repositories
- **4 Consumer containers**: Arch+Flatpak, Ubuntu+Snap, Debian+apt, RHEL+rpm
- **HTTP-based coordination**: Trigger system and results collection

All containers communicate over a pre-created bridge network (`podman-build-network`).

## Development Commands

```bash
# Create the network (one-time setup)
./scripts/create-network.sh

# Run the full orchestration (auto-stops when complete)
./scripts/run-orchestration.sh

# Or run manually
podman-compose up --build --abort-on-container-exit

# Clean up (if needed after manual runs)
podman-compose down
podman network rm podman-build-network
```

**Note**: The orchestration automatically stops all containers when the builder finishes testing. The `--abort-on-container-exit` flag ensures all services shut down cleanly after test results are collected.

## Cleanup Guidelines

**IMPORTANT**: When performing cleanup operations, ONLY target resources specific to this project:

- **Containers**: Only remove containers listed in docker-compose.yml (flatpak-registry, snap-registry, deb-registry, rpm-registry, consumer-arch, consumer-ubuntu, consumer-debian, consumer-redhat, builder)
- **Images**: Only remove images built from this project (test_oskeyring_*)
- **Networks**: Only remove the project network (podman-build-network)
- **Never** run system-wide cleanup commands like `podman system prune` that could affect other projects

Example of safe project-scoped cleanup:
```bash
# Stop and remove only project containers
podman-compose down

# Remove only project-specific images (optional, for full rebuild)
podman rmi $(podman images --filter reference='*test_oskeyring*' -q) 2>/dev/null || true

# Remove only project network
podman network rm podman-build-network 2>/dev/null || true
```

## Key Files

- `docker-compose.yml` - Main orchestration configuration
- `app/` - Sample Rust application (access-keys)
- `builder/` - Build container and packaging scripts
- `registries/` - Package repository containers
- `consumers/` - Distribution-specific test containers
- `consumers/trigger-server/` - Shared HTTP trigger and test runner scripts

## Known Issues

### Flatpak Runtime End-of-Life Warning

During the builder container build, you may see this warning:

```
STEP 3/8: RUN flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo &&     flatpak install -y flathub org.freedesktop.Sdk//23.08 org.freedesktop.Platform//23.08
Looking for matches…

Info: runtime org.freedesktop.Platform branch 23.08 is end-of-life, with reason:
   org.freedesktop.Platform 23.08 is no longer receiving fixes and security updates. Please update to a supported runtime version.
```

This is a non-blocking informational message. The Flatpak runtime version 23.08 is used for demonstration purposes. In production, update to the latest supported runtime version by modifying the version numbers in `builder/Dockerfile` and `builder/build-flatpak.sh`.
