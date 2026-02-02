# Quick Start: VM-Based Snap Testing

This guide helps you get started with the VM-based snap consumer with instant reset capability.

## One-Time Setup

```bash
# 1. Install system dependencies
sudo apt install ansible qemu-system-x86 qemu-utils cloud-image-utils

# 2. Install Ansible collection
ansible-galaxy collection install community.crypto

# 3. Add yourself to kvm group for hardware acceleration
sudo usermod -aG kvm $USER
# IMPORTANT: Log out and back in for this to take effect

# 4. Initialize VM (provision + start + health check)
./scripts/vm-ctl.sh init

# 5. Create snapshot for instant resets (RECOMMENDED)
./scripts/vm-ctl.sh bake
```

After this setup, the VM can be reset to a pristine state in <1 second!

## Running Tests

```bash
# Run the full orchestration (VM + containers)
./scripts/run-orchestration.sh
```

The script will:
1. Check prerequisites (including VM)
2. Create network
3. **Reset VM to clean state** (<1 second if baked image exists)
4. Start VM and wait for it to be ready (15-20s with baked image, 60-90s without)
5. Start all containers
6. Run tests
7. Clean up (stop containers and VM)

**Performance**: With baked image, each test run starts from a pristine VM state instantly!

## Common Commands

```bash
# Quick status dashboard
./scripts/vm-ctl.sh status-full

# Start/stop VM
./scripts/vm-ctl.sh start
./scripts/vm-ctl.sh stop

# Reset VM to clean state (instant)
./scripts/vm-ctl.sh reset

# Watch VM boot process
./scripts/vm-ctl.sh console-log

# SSH into VM
./scripts/vm-ctl.sh ssh

# View service logs
./scripts/vm-ctl.sh logs

# Check VM health
./scripts/vm-ctl.sh health

# Rebuild VM from scratch
./scripts/vm-ctl.sh rebuild
```

**New in this version**: All VM operations now use the improved `vm-ctl.sh` script!

## Troubleshooting

### VM won't start

```bash
# Check KVM is available
ls -l /dev/kvm  # Should show rw access for kvm group

# Verify you're in kvm group
groups | grep kvm  # If not, log out and back in
```

### VM health check times out

```bash
# Watch boot progress in real-time
./scripts/vm-ctl.sh console-log

# Check full status
./scripts/vm-ctl.sh status-full

# Check if VM process is running
ps aux | grep qemu-system-x86_64

# Check VM logs by SSH
./scripts/vm-ctl.sh ssh
sudo systemctl status snap-consumer.service
sudo journalctl -u snap-consumer.service
```

### Tests fail for snap consumer

```bash
# SSH into VM and run test manually
ssh -p 2222 -i vm/ssh/id_ed25519 testrunner@localhost

# Inside VM:
cd /opt/snap-consumer
source consumer.env
bash install.sh
python3 test-runner.py
```

## What Changed?

- **Removed**: `consumer-ubuntu` container (required host security modifications)
- **Added**: QEMU/KVM VM with Ubuntu 24.04 (full isolation, native snapd)
- **Network**: VM uses user-mode networking (no host configuration needed)
- **Access**: Builder triggers VM via `localhost:9002` (port forwarded to VM)

## Architecture

```
Builder (container)
    ↓ triggers
localhost:9002
    ↓ port forward
VM:9000 (snap-consumer-vm)
    ↓ downloads from
10.0.2.2:8081 (slirp gateway)
    ↓ resolves to
localhost:8081
    ↓ exposed by
snap-registry (container)
```

## Benefits

- **Instant Reset**: QCOW2 overlays provide container-like reset speed (<1 second)
- **Fast Boot**: Baked images skip cloud-init (15-20s vs 60-90s)
- **Boot Visibility**: Serial console logging shows progress in real-time
- **No AppArmor modifications** on host
- **No cgroup manipulation**
- **Native systemd and snapd** in VM
- **Easy management**: Unified `vm-ctl.sh` command interface
- **Better isolation**: Full VM isolation

## Performance Comparison

| Operation | Without Baking | With Baking | Speedup |
|-----------|----------------|-------------|---------|
| Reset to clean state | 60-90s (rebuild) | <1s (overlay) | 60-90x |
| Boot after first run | 60-90s (cloud-init) | 15-20s (skip) | 3-4x |
| Full test cycle | 4-5 minutes | 2-3 minutes | 40-50% |

## Learn More

- `vm/README.md` - Comprehensive VM management guide
- `VM_IMPROVEMENTS_SUMMARY.md` - Technical implementation details
- `./scripts/verify-vm-improvements.sh` - Verify installation
- `./scripts/vm-ctl.sh` - Show all available commands
