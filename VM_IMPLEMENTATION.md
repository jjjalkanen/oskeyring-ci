# VM Implementation Summary

This document summarizes the replacement of the `consumer-ubuntu` container with a QEMU/KVM virtual machine.

## Problem Solved

The `consumer-ubuntu` container required extensive host security modifications (AppArmor unconfined, host cgroup access, security mounts) that were fragile and didn't work reliably. The VM provides full isolation with native systemd, snapd, and AppArmor support.

## Architecture

```
Host Machine (no security modifications)
│
├── Podman containers (podman-build-network)
│   ├── builder:9999 (exposed on host)
│   ├── snap-registry:8081 (exposed on host)
│   ├── flatpak-registry:8080
│   ├── deb-registry:8082
│   ├── rpm-registry:8083
│   ├── consumer-arch:9000
│   ├── consumer-debian:9000
│   └── consumer-redhat:9000
│
└── QEMU VM (user-mode networking)
    ├── 10.0.2.2 = host gateway (slirp)
    ├── Port 9000 → host:9002
    └── snap-consumer-vm (Ubuntu 24.04)
        ├── snapd (native)
        ├── AppArmor (native)
        └── trigger-server:9000
```

## Network Flow

1. **Builder triggers VM**: `host.containers.internal:9002` → VM:9000
2. **VM downloads snap**: `10.0.2.2:8081` → host → snap-registry
3. **VM reports results**: `10.0.2.2:9999` → host → builder

All networking uses QEMU user-mode (slirp) - no bridges, no iptables, no IP forwarding changes.

## Files Created

### Ansible Infrastructure
- `ansible/ansible.cfg` - Ansible configuration
- `ansible/inventory/hosts.yml` - Inventory (localhost)
- `ansible/vars/vm-config.yml` - VM configuration variables
- `ansible/playbooks/vm-provision.yml` - VM provisioning playbook
- `ansible/playbooks/vm-stop.yml` - Stop VM playbook
- `ansible/playbooks/vm-destroy.yml` - Destroy VM playbook
- `ansible/roles/snap_consumer/templates/user-data.j2` - Cloud-init config
- `ansible/README.md` - Documentation

### Scripts
- `scripts/vm-health-check.sh` - Wait for VM readiness

### Runtime Directories (gitignored)
- `vm/images/` - Downloaded cloud images
- `vm/disks/` - VM disk files
- `vm/ssh/` - Generated SSH keys

## Files Modified

### docker-compose.yml
- **Removed**: `consumer-ubuntu` service (lines 51-74)
- **Updated**: Builder `depends_on` (removed consumer-ubuntu)
- Ports already exposed for snap-registry:8081 and builder:9999

### builder/scripts/trigger-consumers.sh
- Changed `consumer-ubuntu:9000` → `host.containers.internal:9002`

### scripts/run-orchestration.sh
- Added VM lifecycle functions (`start_vm`, `stop_vm`)
- Added `check_vm_prerequisites` check
- Updated prerequisite check (added qemu requirement, removed snap-specific checks)
- Modified cleanup to stop VM
- Added VM start step before container launch

### .gitignore
- Added VM artifact patterns

## Usage

### First Time Setup

```bash
# Install prerequisites
sudo apt install ansible qemu-system-x86 qemu-utils cloud-image-utils
ansible-galaxy collection install community.crypto
sudo usermod -aG kvm $USER
# Log out and back in

# Provision VM
cd ansible
ansible-playbook playbooks/vm-provision.yml
cd ..
```

### Run Orchestration

```bash
./scripts/run-orchestration.sh
```

The script now:
1. Checks prerequisites (including VM provisioning)
2. Creates network
3. **Starts VM** and waits for health check
4. Starts containers
5. Waits for completion
6. Stops containers **and VM**

### Manual VM Management

```bash
# Stop VM
cd ansible
ansible-playbook playbooks/vm-stop.yml

# Destroy and rebuild VM
ansible-playbook playbooks/vm-destroy.yml
ansible-playbook playbooks/vm-provision.yml

# SSH into VM
ssh -p 2222 -i vm/ssh/id_ed25519 testrunner@localhost
```

## Benefits

1. **No host security modifications**: VM is fully isolated
2. **Native snap/AppArmor**: Works exactly like a real Ubuntu system
3. **Clean networking**: User-mode QEMU networking, no iptables
4. **Easy cleanup**: Kill QEMU process = VM stopped
5. **Reproducible**: Cloud-init makes VM provisioning idempotent

## Prerequisites

- QEMU/KVM with hardware acceleration
- Ansible with community.crypto collection
- cloud-image-utils (for cloud-localds)
- User in `kvm` group

## Verification Steps

```bash
# 1. Provision VM
cd ansible && ansible-playbook playbooks/vm-provision.yml && cd ..

# 2. Test VM standalone
qemu-system-x86_64 \
  -name snap-consumer-vm \
  -m 2048 -smp 2 -enable-kvm \
  -drive file=vm/disks/snap-consumer-vm.qcow2,format=qcow2 \
  -drive file=vm/disks/snap-consumer-vm-cidata.iso,format=raw \
  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::9002-:9000 \
  -device virtio-net-pci,netdev=net0 \
  -display none -daemonize -pidfile /tmp/snap-consumer-vm.pid

# Wait for boot
sleep 30

# Check health
curl http://localhost:9002/health  # Should return "OK"

# Stop VM
kill $(cat /tmp/snap-consumer-vm.pid)

# 3. Run full orchestration
./scripts/run-orchestration.sh
```

Expected result: All 4 consumers pass (arch, ubuntu/VM, debian, redhat)
