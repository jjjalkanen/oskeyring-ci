# Ansible VM Provisioning

This directory contains Ansible playbooks for managing the snap-consumer VM that replaces the problematic `consumer-ubuntu` container.

## Prerequisites

```bash
# Install Ansible and required collections
sudo apt install ansible

# Install community.crypto collection for SSH key generation
ansible-galaxy collection install community.crypto

# Install QEMU/KVM
sudo apt install qemu-system-x86 qemu-utils cloud-image-utils

# Add user to kvm group for hardware acceleration
sudo usermod -aG kvm $USER
# Log out and back in for group changes to take effect
```

## VM Provisioning

### Initial Setup

```bash
cd ansible
ansible-playbook playbooks/vm-provision.yml
```

This will:
1. Download Ubuntu 24.04 cloud image
2. Create a VM disk image
3. Generate SSH keys for VM access
4. Create cloud-init configuration
5. Provision the VM with snapd and trigger server

### VM Management

The VM is automatically managed by `scripts/run-orchestration.sh`, but you can also control it manually:

```bash
# Stop the VM
ansible-playbook playbooks/vm-stop.yml

# Destroy the VM (removes disk images)
ansible-playbook playbooks/vm-destroy.yml

# Recreate after destruction
ansible-playbook playbooks/vm-provision.yml
```

### Manual VM Control

If needed, you can start the VM manually:

```bash
qemu-system-x86_64 \
  -name snap-consumer-vm \
  -m 2048 \
  -smp 2 \
  -enable-kvm \
  -drive file=../vm/disks/snap-consumer-vm.qcow2,format=qcow2 \
  -drive file=../vm/disks/snap-consumer-vm-cidata.iso,format=raw \
  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::9002-:9000 \
  -device virtio-net-pci,netdev=net0 \
  -nographic
```

### SSH Access

```bash
# SSH into the VM
ssh -p 2222 -i ../vm/ssh/id_ed25519 testrunner@localhost
```

## Architecture

The VM uses QEMU user-mode networking (slirp):
- **Host → VM**: Port 9002 on host forwards to port 9000 in VM (trigger server)
- **VM → Host**: VM sees host as `10.0.2.2` (slirp gateway)
- **VM → Registries**: Accesses via `10.0.2.2:8081` (snap-registry)
- **VM → Builder**: Reports results via `10.0.2.2:9999`

No host network configuration changes required - all networking is userspace.

## Configuration

VM settings can be customized in `vars/vm-config.yml`:
- VM resources (memory, CPUs, disk size)
- Network port mappings
- Ubuntu version
- Service URLs

## Troubleshooting

### VM won't start
```bash
# Check if KVM is available
ls -l /dev/kvm
# Should show rw access for kvm group

# Check if you're in kvm group
groups | grep kvm
```

### VM not responding
```bash
# Check health endpoint
curl http://localhost:9002/health
# Should return "OK"

# Check VM logs (if running in foreground)
# Or SSH in and check service status
ssh -p 2222 -i ../vm/ssh/id_ed25519 testrunner@localhost
sudo systemctl status snap-consumer.service
```

### Rebuild VM from scratch
```bash
ansible-playbook playbooks/vm-destroy.yml
ansible-playbook playbooks/vm-provision.yml
```
