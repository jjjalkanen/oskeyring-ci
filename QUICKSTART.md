# Quick Start Guide

## Complete Setup from Scratch

Follow these steps to set up and run the complete orchestration system.

### 1. Install Prerequisites

```bash
# Install required packages
sudo apt install podman podman-compose qemu-system-x86 cloud-image-utils ansible

# Add your user to the kvm group for hardware acceleration
sudo usermod -aG kvm $USER

# Log out and back in for group changes to take effect
# Or run: newgrp kvm
```

### 2. Install Ansible Collections

```bash
ansible-galaxy collection install community.crypto
```

### 3. Provision the VM

```bash
cd ansible
ansible-playbook playbooks/vm-provision.yml
cd ..
```

This will:
- Download Ubuntu 24.04 cloud image (~700MB)
- Create VM disk image
- Generate SSH keys
- Configure cloud-init with snapd and trigger server

Expected output: "VM provisioned! Start with: ..."

### 4. Run the Orchestration

```bash
./scripts/run-orchestration.sh
```

This script automatically:
1. Creates the Podman network
2. Starts the snap consumer VM
3. Launches all containers
4. Waits for tests to complete
5. Shows results and cleans up

### 5. Expected Results

You should see:

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

## Troubleshooting

### VM Provisioning Issues

**Problem**: KVM not available
```bash
# Check KVM device
ls -l /dev/kvm
# Should show: crw-rw---- 1 root kvm

# Verify you're in kvm group
groups | grep kvm

# If not in group
sudo usermod -aG kvm $USER
newgrp kvm
```

**Problem**: Download fails
```bash
# Manually download the cloud image
wget https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img \
  -O vm/images/ubuntu-24.04-cloudimg.img
```

### VM Runtime Issues

**Problem**: VM not responding
```bash
# Check VM health
curl http://localhost:9002/health
# Should return: OK

# Check if VM is running
ps aux | grep qemu | grep snap-consumer-vm

# View VM PID
cat /tmp/snap-consumer-vm.pid
```

**Problem**: VM won't start
```bash
# Check for existing VM
kill $(cat /tmp/snap-consumer-vm.pid) 2>/dev/null

# Try manual start (foreground for debugging)
qemu-system-x86_64 \
  -name snap-consumer-vm \
  -m 2048 -smp 2 -enable-kvm \
  -drive file=vm/disks/snap-consumer-vm.qcow2,format=qcow2 \
  -drive file=vm/disks/snap-consumer-vm-cidata.iso,format=raw \
  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::9002-:9000 \
  -device virtio-net-pci,netdev=net0 \
  -nographic
```

### Orchestration Issues

**Problem**: Containers fail to start
```bash
# Check network exists
podman network ls | grep podman-build-network

# Recreate network if needed
./scripts/create-network.sh

# Check container status
podman ps -a
```

**Problem**: Tests fail
```bash
# View detailed builder logs
podman logs builder

# Check specific consumer logs
podman logs consumer-arch
podman logs consumer-debian
podman logs consumer-redhat

# For VM logs, SSH in
ssh -p 2222 -i vm/ssh/id_ed25519 testrunner@localhost
sudo journalctl -u snap-consumer.service
```

## Manual Testing

### Test VM Independently

```bash
# Start VM manually
cd ansible
ansible-playbook playbooks/vm-provision.yml
cd ..

# Start VM in background
qemu-system-x86_64 ... -daemonize -pidfile /tmp/snap-consumer-vm.pid

# Wait for boot
./scripts/vm-health-check.sh

# Trigger test
curl -X POST http://localhost:9002/trigger

# SSH into VM
ssh -p 2222 -i vm/ssh/id_ed25519 testrunner@localhost

# Check service status
sudo systemctl status snap-consumer.service
sudo journalctl -u snap-consumer.service -f
```

### Test Individual Components

```bash
# Start only registries and one consumer
podman-compose up snap-registry consumer-arch

# Manually trigger
curl http://localhost:9001/health
curl -X POST http://localhost:9001/trigger
```

## Clean Rebuild

```bash
# Stop everything
podman-compose down
cd ansible && ansible-playbook playbooks/vm-stop.yml && cd ..

# Destroy VM
cd ansible && ansible-playbook playbooks/vm-destroy.yml && cd ..

# Remove network
podman network rm podman-build-network

# Clean images (optional)
podman rmi $(podman images --filter reference='*test_oskeyring*' -q) 2>/dev/null || true

# Start fresh
cd ansible && ansible-playbook playbooks/vm-provision.yml && cd ..
./scripts/run-orchestration.sh
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ Host Machine                                                │
│                                                             │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Podman Network (podman-build-network)              │    │
│  │                                                     │    │
│  │  ├─ flatpak-registry:8080  (→ host:8080)          │    │
│  │  ├─ snap-registry:8081     (→ host:8081) ─────┐   │    │
│  │  ├─ deb-registry:8082      (→ host:8082)     │   │    │
│  │  ├─ rpm-registry:8083      (→ host:8083)     │   │    │
│  │  ├─ consumer-arch:9000                        │   │    │
│  │  ├─ consumer-debian:9000                      │   │    │
│  │  ├─ consumer-redhat:9000                      │   │    │
│  │  └─ builder:9999           (→ host:9999) ────┼─┐ │    │
│  └─────────────────────────────────────────────┼─┼─┘    │
│                                                 │ │      │
│  Host Ports:                                    │ │      │
│  ├─ localhost:9002 (→ VM:9000) ◄───────────────┼─┘      │
│  └─ localhost:2222 (→ VM:22)                   │        │
│                                                 │        │
│  ┌──────────────────────────────────────────┐  │        │
│  │ QEMU VM (user-mode networking)           │  │        │
│  │                                           │  │        │
│  │  snap-consumer-vm (Ubuntu 24.04)         │  │        │
│  │  ├─ snapd (native, working)              │  │        │
│  │  ├─ AppArmor (native, working)           │  │        │
│  │  └─ trigger-server:9000                  │  │        │
│  │                                           │  │        │
│  │  Network (10.0.2.2 = slirp gateway):     │  │        │
│  │  ├─ 10.0.2.2:8081 → snap-registry ───────┼──┘        │
│  │  └─ 10.0.2.2:9999 → builder              │           │
│  └──────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────┘
```

## Next Steps

- Customize VM resources in `ansible/vars/vm-config.yml`
- Modify the test application in `app/`
- Add more package formats or consumers
- Integrate with CI/CD pipelines

For more details, see:
- `README.md` - Full project documentation
- `ansible/README.md` - VM provisioning details
- `CLAUDE.md` - Development guidance
