# Podman Container Orchestration Test System

This repository implements a complete container orchestration system for building, distributing, and testing software packages across multiple Linux distributions and package formats.

## Architecture

The system consists of:
- **1 Builder container**: Compiles Rust application and packages into 4 formats
- **4 Registry containers**: Flatpak, Snap, Debian (apt), and RPM repositories
- **3 Consumer containers**: Arch+Flatpak, Debian+apt, RHEL+rpm
- **1 Consumer VM**: Ubuntu+Snap (QEMU/KVM for native snapd/AppArmor support)
- **HTTP trigger system**: Orchestrates installation and testing
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
3. **Publish Phase**: Uploads packages to respective registry containers
4. **Trigger Phase**: Notifies all consumer containers to begin testing
5. **Test Phase**: Each consumer installs and tests the package
6. **Report Phase**: Consumers send results back to builder
7. **Summary Phase**: Builder outputs final test results and exits

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
Distribution-specific containers that:
- Listen for HTTP triggers on port 9000
- Install packages from registries
- Run tests
- Report results back to builder

### Scripts (`scripts/`)
Helper scripts for network setup and orchestration.

## Manual Testing

You can manually trigger consumers:

```bash
# Check consumer health
curl http://localhost:9001/health  # Arch
curl http://localhost:9002/health  # Ubuntu VM
curl http://localhost:9003/health  # Debian
curl http://localhost:9004/health  # RHEL

# Manually trigger a consumer
curl -X POST http://localhost:9001/trigger

# SSH into the VM (if needed)
ssh -p 2222 -i vm/ssh/id_ed25519 testrunner@localhost
```

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

## Design Decisions

- **Ephemeral registries**: No persistent volumes, fresh on each run
- **Synchronous pipeline**: End-to-end flow from build to test report
- **HTTP-based coordination**: Simple trigger and report mechanism
- **Parallel testing**: All consumers test simultaneously after trigger
- **VM for Snap testing**: Ubuntu consumer runs in QEMU/KVM VM for native snapd/AppArmor support
  - QEMU user-mode networking (slirp) - no host security modifications needed
  - Full systemd, AppArmor, and snap confinement support
  - Cloud-init for automated provisioning
