# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CI system that builds Firefox (with oskeyring/credential support), packages it into 4 Linux formats (Flatpak, Snap, DEB, RPM), distributes packages to registry containers, and runs end-to-end tests on consumer distros to verify credential storage works correctly per-platform.

## Architecture

### Pipeline Flow

1. **Host build** (`run-orchestration.sh`): Compiles Firefox from `firefox/` source tree using `./mach build` and `./mach package`, builds the `access-keys` canary app and `credential-server` Rust binaries, outputs artifacts to `dist/`
2. **Container build**: Builds registry and consumer container images via `podman-compose`
3. **Builder container** (`builder/scripts/entrypoint.sh`): Validates artifacts, publishes packages to registries, starts results collector, triggers consumers
4. **Consumer testing**: Each consumer installs packages via its native package manager, runs credential storage tests, IDB encryption verification, and WPT tests, then reports results back to the builder's results collector

### Two Build Flavors

Firefox is compiled twice when all consumers are selected:
- **Host-native** (`builder/scripts/firefox-mozconfig`): Used by DEB, Flatpak, and Snap consumers. Output in `obj-fx-dbg/`
- **RHEL9-targeted** (`builder/scripts/firefox-mozconfig-rhel9`): Used by RPM consumer only. Requires pre-built onnxruntime at `dist/onnxruntime-rhel9/`. Output in `obj-fx-rhel9/`

### Consumer Credential Models

Each consumer tests a different Linux credential storage mechanism:
- **consumer-arch** (Flatpak): Secret Portal via D-Bus + gnome-keyring. Runs in privileged container for bwrap user namespaces
- **consumer-ubuntu** (Snap): `SNAP_DATA` file-based storage. Runs in QEMU/KVM VM (not container) for native snapd/AppArmor
- **consumer-debian** (DEB): `systemd-creds encrypt` → `LoadCredentialEncrypted` via `CREDENTIALS_DIRECTORY`. Runs in QEMU VM
- **consumer-redhat** (RPM): Same systemd credential model as Debian. Runs in privileged container with cgroup mount

### Network Topology

Containers share `podman-build-network` bridge. VMs use QEMU user-mode networking (slirp) — they reach containers via `10.0.2.2` (gateway to host), and the host reaches VMs via port forwards (SSH 2222/2223, trigger 9002/9003). No iptables or host networking changes required.

### Shared Test Infrastructure

`consumers/trigger-server/` contains scripts shared across all consumers:
- `server.py` — HTTP server: `GET /health` + `POST /trigger` (triggers upgrade → test → report pipeline)
- `test-runner.py` — Per-platform credential verification tests
- `idb-verify.py` — IndexedDB encryption verification against a running Firefox
- `wpt-runner.py` — Web Platform Tests execution

## Development Commands

```bash
# Full orchestration (builds Firefox, packages, tests everything)
./scripts/run-orchestration.sh

# Run specific consumers only
./scripts/run-orchestration.sh --consumer consumer-arch --consumer consumer-debian

# Build Firefox only (no containers/VMs)
./scripts/run-orchestration.sh --build-only

# Skip Firefox build, repackage with existing artifacts
./scripts/run-orchestration.sh --no-build

# Override mozconfig mismatch checks
./scripts/run-orchestration.sh --force-build

# Provision VMs (required before first run with snap/deb consumers)
cd ansible && ansible-playbook playbooks/vm-provision.yml    # snap VM
cd ansible && ansible-playbook playbooks/deb-vm-provision.yml  # deb VM

# Bake VMs (snapshot after provisioning for faster restarts)
cd ansible && ansible-playbook playbooks/vm-bake.yml
cd ansible && ansible-playbook playbooks/deb-vm-bake.yml

# Build RHEL9 onnxruntime (prerequisite for consumer-redhat)
./scripts/build-onnxruntime-rhel9.sh
```

### Manual Debugging

```bash
# Check consumer health
curl http://localhost:9001/health  # Arch
curl http://localhost:9002/health  # Ubuntu VM
curl http://localhost:9003/health  # Debian VM
curl http://localhost:9004/health  # RHEL

# SSH into VMs
ssh -p 2222 -i vm/ssh/id_ed25519 testrunner@localhost   # snap VM
ssh -p 2223 -i vm/ssh/id_ed25519 consumer@localhost     # deb VM

# View consumer logs
podman exec consumer-arch cat /tmp/trigger.log
podman exec consumer-redhat journalctl -u trigger-server.service -f
```

## Cleanup Guidelines

**Only target project-specific resources.** Never run `podman system prune` or similar system-wide cleanup.

```bash
podman-compose down
podman network rm podman-build-network 2>/dev/null || true
# VMs
cd ansible && ansible-playbook playbooks/vm-stop.yml
cd ansible && ansible-playbook playbooks/vm-destroy.yml  # requires re-provisioning
```

Container names: `flatpak-registry`, `snap-registry`, `deb-registry`, `rpm-registry`, `consumer-arch`, `consumer-redhat`, `builder`. Images are prefixed `test_oskeyring_*`.

## Key Conventions

- The `dist/` directory is the handoff point between host builds and container builds. The builder container mounts it read-only
- `run-orchestration.sh` validates mozconfigs match canonical configs before building — use `--force-build` to override
- Consumer Dockerfiles use `consumers/` as build context (not the consumer subdirectory), so `COPY` paths reference `trigger-server/` and the consumer-specific subdirectory
- Registry containers are ephemeral nginx instances with no persistent volumes
- The `ENABLED_CONSUMERS` env var (comma-separated) filters which consumers the builder triggers
- `env -u CLAUDECODE` is used before `./mach` commands to prevent Claude Code env vars from leaking into the Firefox build
