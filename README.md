# Podman Container Orchestration Test System

This repository implements a complete container orchestration system for building, distributing, and testing software packages across multiple Linux distributions and package formats.

## Architecture

The system consists of:
- **1 Builder container**: Compiles Rust application and packages into 4 formats
- **4 Registry containers**: Flatpak, Snap, Debian (apt), and RPM repositories
- **3 Consumer containers**: Arch+Flatpak, Debian+apt, RHEL+rpm
- **1 Consumer VM**: Ubuntu+Snap (QEMU/KVM for native snapd/AppArmor support)
- **Auto-update detection**: Consumers automatically detect and install packages using OS-native mechanisms
- **Unprivileged monitors**: Each consumer runs a monitoring service as non-root user
- **Results collector**: Aggregates test results from all consumers

## Quick Start

### Prerequisites

Install required tools:
```bash
sudo apt install podman podman-compose qemu-system-x86 cloud-image-utils ansible
```

Install Ansible community crypto collection:
```bash
ansible-galaxy collection install community.crypto
```

### Provision the VM

The Snap consumer runs in a VM for native snapd/AppArmor support:

```bash
cd ansible
ansible-playbook playbooks/vm-provision.yml
cd ..
```

### Run the Orchestration

```bash
./scripts/run-orchestration.sh
```

This script will:
1. Create the Podman network
2. Start the snap consumer VM
3. Launch all containers
4. Wait for tests to complete
5. Show results and clean up

## Pipeline Flow

1. **Build Phase**: Builder compiles the `access-keys` Rust application
2. **Package Phase**: Creates Flatpak, Snap, .deb, and .rpm packages
3. **Collector Phase**: Builder starts results collector (must be ready before packages appear)
4. **Health Check**: Builder verifies all consumers are responsive
5. **Publish Phase**: Uploads packages to respective registry containers
6. **Auto-Detection Phase**: Consumers automatically detect new packages (2-5 second polling)
   - Debian/RedHat: systemd timers check for upgrades from v0.0.1 → v0.1.0
   - Arch/Ubuntu: Background processes retry installation until successful
7. **Install Phase**: Auto-updaters install packages using native package managers
8. **Test Phase**: Auto-updaters run tests and write results.json (consumer-owned)
9. **Report Phase**: Unprivileged monitors detect results.json and POST to builder
10. **Summary Phase**: Builder outputs final test results and exits

## Network Architecture

### Container Network
Containers communicate over the `podman-build-network` bridge:

- `flatpak-registry:8080` - Flatpak/OSTree repository (exposed to host:8080)
- `snap-registry:8081` - Snap store (exposed to host:8081)
- `deb-registry:8082` - APT repository (exposed to host:8082)
- `rpm-registry:8083` - RPM repository (exposed to host:8083)
- `consumer-arch:9000` - Arch Linux consumer (Flatpak)
- `consumer-debian:9000` - Debian consumer (APT)
- `consumer-redhat:9000` - RHEL consumer (RPM)
- `builder:9999` - Results collection endpoint (exposed to host:9999)

### VM Network (QEMU user-mode networking)
The snap consumer VM uses QEMU's built-in user-mode networking (slirp):

- VM accesses containers via `10.0.2.2` (slirp gateway to host)
  - `10.0.2.2:8081` → snap-registry
  - `10.0.2.2:9999` → builder
- Host accesses VM via port forwarding:
  - `localhost:2222` → VM SSH (port 22)
  - `localhost:9002` → VM trigger server (port 9000)
- Builder triggers VM via `host.containers.internal:9002`

This approach requires **no host networking changes** (no iptables, no bridges, no IP forwarding).

## Expected Output

When all tests pass, you should see:

```
================================================================================
TEST RESULTS SUMMARY
================================================================================

✓ consumer-arch: PASS
  Output: All good

✓ consumer-ubuntu: PASS
  Output: All good

✓ consumer-debian: PASS
  Output: All good

✓ consumer-redhat: PASS
  Output: All good

================================================================================
RESULT: ALL TESTS PASSED
================================================================================
```

The builder container will exit with code 0 if all tests pass, or 1 if any fail.

## Components

### Application (`app/`)
Simple Rust application that prints "All good" when executed.

### Builder (`builder/`)
Fedora-based container with tooling for all package formats. Orchestrates the entire pipeline.

### Registries (`registries/`)
Nginx-based containers serving package repositories:
- `flatpak/` - OSTree/Flatpak repository
- `snap/` - Snap store mock
- `deb/` - APT repository with Packages.gz
- `rpm/` - YUM/DNF repository with repodata

### Consumers (`consumers/`)
Distribution-specific containers with two components:

**Auto-updaters** (run as root):
- Poll for package updates using OS-native mechanisms
- Debian/RedHat: systemd timers (every 2s) check `apt`/`dnf` for upgrades
- Arch: Background process retries `flatpak install` until successful
- Install packages, set up credentials, run tests
- Write results to `/home/consumer/results.json`

**Monitors** (run as unprivileged `consumer` user):
- Serve health checks on port 9000 (`GET /health`)
- Watch for `/home/consumer/results.json` in background thread
- Report results to builder with retry logic (60 attempts, 2s interval)

### Scripts (`scripts/`)
Helper scripts for network setup and orchestration.

## Manual Testing

You can check consumer health and monitor logs:

```bash
# Check consumer monitor health
curl http://localhost:9001/health  # Arch
curl http://localhost:9002/health  # Ubuntu VM
curl http://localhost:9003/health  # Debian
curl http://localhost:9004/health  # RHEL

# View consumer logs (systemd consumers)
podman exec consumer-debian journalctl -u trigger-server.service -f
podman exec consumer-debian journalctl -u access-keys-updater.timer -f

# Check if results were written
podman exec consumer-debian cat /home/consumer/results.json

# SSH into the VM (if needed)
ssh -p 2222 -i vm/ssh/id_ed25519 testrunner@localhost
```

**Note**: The old `POST /trigger` endpoint has been removed. Consumers now auto-detect packages.

## Troubleshooting

### Consumers not detecting packages
Check auto-updater status:
```bash
# Debian/RedHat (systemd timers)
podman exec consumer-debian systemctl status access-keys-updater.timer
podman exec consumer-debian journalctl -u access-keys-updater.service

# Arch (background process)
podman exec consumer-arch ps aux | grep auto-updater
```

### Permission denied errors
Verify file ownership:
```bash
podman exec consumer-debian ls -la /home/consumer/
# results.json should be consumer:consumer (644)
# server.py should be consumer:consumer (755)
```

### Monitor not reporting results
Check monitor logs:
```bash
podman exec consumer-debian journalctl -u trigger-server.service -f
# Should see: "Waiting for test results..."
# Then: "Results found, reporting to builder..."
```

### Tests timing out
- Auto-detection takes 2-10 seconds after packages are published
- Installation may take 10-30 seconds depending on package format
- Total expected time: 30-60 seconds from publish to results

See `TROUBLESHOOTING.md` for more details.

## Cleaning Up

```bash
# Stop containers and VM
podman-compose down

# Stop VM (if running standalone)
cd ansible && ansible-playbook playbooks/vm-stop.yml

# Remove the network
podman network rm podman-build-network

# Destroy VM completely (optional - requires re-provisioning)
cd ansible && ansible-playbook playbooks/vm-destroy.yml

# Clean up images (optional)
podman image prune -a
```

## Requirements

- Podman and podman-compose
- QEMU/KVM (qemu-system-x86_64 with KVM support)
- cloud-image-utils (cloud-localds for cloud-init)
- Ansible with community.crypto collection
- User must be in `kvm` group for hardware acceleration
- Linux host (tested on Linux 6.14.0)

## Security Architecture

### Privilege Separation
- **Monitors**: Run as unprivileged `consumer` user (UID 1000)
  - Read-only file watching for results
  - Cannot modify system state
  - Isolated via systemd `User=` directive (Debian/RedHat) or `su` (Arch)

- **Auto-updaters**: Run as root (required for package installation)
  - Isolated to specific tasks (install, test, write results)
  - No network-facing HTTP endpoints
  - Triggered by systemd timers (Debian/RedHat) or background processes (Arch)

### Attack Surface Reduction
- ❌ **Removed**: Root HTTP server accepting POST requests
- ✅ **Added**: Unprivileged monitors with health-check-only endpoints
- ✅ **Added**: OS-native package polling (apt, dnf, flatpak)
- ✅ **Added**: File-based coordination (results.json)

## Design Decisions

- **Ephemeral registries**: No persistent volumes, fresh on each run
- **Synchronous pipeline**: End-to-end flow from build to test report
- **Auto-update detection**: Consumers poll for packages using OS-native mechanisms (apt, dnf, flatpak)
- **Privilege separation**: Monitors run as unprivileged users, only installers run as root
- **Parallel testing**: All consumers test simultaneously after packages are published
- **No manual triggers**: System uses polling instead of HTTP POST triggers for better security
- **VM for Snap testing**: Ubuntu consumer runs in QEMU/KVM VM for native snapd/AppArmor support
  - QEMU user-mode networking (slirp) - no host security modifications needed
  - Full systemd, AppArmor, and snap confinement support
  - Cloud-init for automated provisioning
