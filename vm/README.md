# VM Management Guide

This document explains the snap-consumer VM setup and management using instant reset snapshots.

## Quick Start

```bash
# One-time setup (takes ~60-90 seconds)
./scripts/vm-ctl.sh init

# Enable instant resets (run after VM is healthy)
./scripts/vm-ctl.sh bake

# Daily usage (instant clean state before each test)
./scripts/run-orchestration.sh
```

## Architecture

The VM uses QCOW2 overlay files for instant resets:

```
┌─────────────────────────────────────────┐
│ snap-consumer-vm-overlay.qcow2 (thin)   │  ← Changes during test
│ Backing: snap-consumer-vm-baked.qcow2   │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ snap-consumer-vm-baked.qcow2 (read-only)│  ← Clean state (snapd configured)
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ snap-consumer-vm.qcow2 (base image)     │  ← Original provisioned VM
└─────────────────────────────────────────┘
```

## Workflow

### Initial Setup

1. **Provision the VM** (creates base disk):
   ```bash
   ./scripts/vm-ctl.sh provision
   ```

2. **Start the VM** (runs cloud-init on first boot):
   ```bash
   ./scripts/vm-ctl.sh start
   ```
   This takes ~60-90 seconds as cloud-init:
   - Updates packages
   - Installs and configures snapd
   - Sets up trigger server
   - Starts services

3. **Bake the image** (create clean snapshot):
   ```bash
   ./scripts/vm-ctl.sh bake
   ```
   This flattens the current VM state into a "baked" image that can be used for instant resets.

### Daily Usage

Once baked, the VM uses overlay files automatically:

```bash
# Run full orchestration (instant reset + test)
./scripts/run-orchestration.sh
```

The orchestration script:
1. Deletes the old overlay (discards all changes)
2. Creates a fresh overlay from the baked image (<1 second)
3. Boots the VM (skips cloud-init, ~15-20 seconds)
4. Runs tests in pristine environment
5. Cleans up

### Manual Operations

```bash
# Reset VM to clean state without running tests
./scripts/vm-ctl.sh reset
./scripts/vm-ctl.sh start

# Check VM status
./scripts/vm-ctl.sh status-full

# Watch boot progress
./scripts/vm-ctl.sh console-log

# Rebuild everything from scratch
./scripts/vm-ctl.sh rebuild
```

## Command Reference

| Command | Description | Use Case |
|---------|-------------|----------|
| `init` | Provision + start + wait | One-time setup |
| `start` | Start the VM | Boot VM after stop |
| `stop` | Stop the VM | Graceful shutdown |
| `restart` | Stop + start | Reboot VM |
| `status` | Check if running | Quick check |
| `health` | Check health endpoint | Verify VM responds |
| `status-full` | Comprehensive dashboard | Troubleshooting |
| `bake` | Create baked image | Enable instant resets |
| `reset` | Instant clean state | Manual pristine reset |
| `rebuild` | Destroy + provision + start | Start over completely |
| `console-log` | Tail serial console | Watch boot progress |
| `ssh` | SSH into VM | Manual debugging |
| `logs` | View service logs | Check trigger server |
| `provision` | Create base VM | Initial setup |
| `destroy` | Delete VM disk | Clean slate |

## Timing Comparison

| Operation | Without Baked Image | With Baked Image |
|-----------|---------------------|------------------|
| First boot (cloud-init) | ~60-90 seconds | ~60-90 seconds |
| Subsequent boots | ~60-90 seconds (cloud-init runs) | ~15-20 seconds (skips cloud-init) |
| Reset to clean state | N/A (reinstall or rebuild) | <1 second (overlay delete/create) |
| Full test run | ~4-5 minutes | ~2-3 minutes |

## Troubleshooting

### VM won't start after baking

Check the baked image exists:
```bash
ls -lh vm/disks/snap-consumer-vm-baked.qcow2
```

If missing, re-bake:
```bash
./scripts/vm-ctl.sh start
./scripts/vm-ctl.sh bake
```

### Health check timeout

Watch boot progress:
```bash
# Terminal 1
./scripts/vm-ctl.sh start

# Terminal 2
./scripts/vm-ctl.sh console-log
```

Look for `[cloud-init] READY` in the console log.

### Overlay file corruption

Reset the overlay:
```bash
./scripts/vm-ctl.sh stop
rm vm/disks/snap-consumer-vm-overlay.qcow2
./scripts/vm-ctl.sh start
```

### Need to rebuild baked image

If you need to update the base configuration (e.g., install new packages):

```bash
# 1. Destroy overlay and baked image
./scripts/vm-ctl.sh stop
rm vm/disks/snap-consumer-vm-overlay.qcow2
rm vm/disks/snap-consumer-vm-baked.qcow2

# 2. Boot from base, make changes
./scripts/vm-ctl.sh start
./scripts/vm-ctl.sh ssh
# ... make changes ...
# exit

# 3. Re-bake
./scripts/vm-ctl.sh bake
```

## Files

| File | Purpose |
|------|---------|
| `disks/snap-consumer-vm.qcow2` | Base disk (from cloud-init) |
| `disks/snap-consumer-vm-baked.qcow2` | Flattened clean state |
| `disks/snap-consumer-vm-overlay.qcow2` | Thin overlay with changes |
| `disks/snap-consumer-vm-cidata.iso` | Cloud-init data |
| `disks/snap-consumer-vm-baked.timestamp` | Bake creation time |
| `logs/console.log` | Serial console output |
| `ssh/id_ed25519` | SSH private key |
| `ssh/id_ed25519.pub` | SSH public key |

## Integration with Containers

The VM runs alongside containers in the orchestration:

```
┌─────────────────┐
│ Builder (Fedora)│───────┐
└─────────────────┘       │
                          │
┌─────────────────┐       │  HTTP requests
│ 4x Registries   │       │  (nginx serving repos)
└─────────────────┘       │
                          │
┌─────────────────┐       │
│ 4x Containers   │◄──────┤
│ (Flatpak/Deb/   │       │
│  RPM consumers) │       │
└─────────────────┘       │
                          │
┌─────────────────┐       │
│ VM (Snap)       │◄──────┘
│ - Fresh overlay │
│ - No cloud-init │
│ - Fast boot     │
└─────────────────┘
```

The VM receives test triggers over HTTP and reports results back to the builder, just like the containers.

## Why Overlays?

Containers can be rebuilt instantly. VMs traditionally require:
- Full cloud-init run (~60-90s)
- Or manual cleanup (unreliable)
- Or full disk copy (slow)

QCOW2 overlays provide:
- **Instant reset** - Delete + create overlay (<1s)
- **Fast boot** - Skips cloud-init (~15-20s vs ~60-90s)
- **Guaranteed clean state** - Every test starts from identical snapshot
- **Container-like experience** - Same workflow as Podman containers

This makes the VM as convenient as containers for repeated testing.
