# Testing Checklist

This document provides a comprehensive testing checklist to verify the VM-based snap consumer implementation.

## Pre-Flight Checks

### 1. System Prerequisites

```bash
# Check all required commands are available
command -v podman && echo "✓ podman"
command -v podman-compose && echo "✓ podman-compose"
command -v qemu-system-x86_64 && echo "✓ qemu"
command -v cloud-localds && echo "✓ cloud-image-utils"
command -v ansible && echo "✓ ansible"
command -v ansible-galaxy && echo "✓ ansible-galaxy"

# Check KVM access
ls -l /dev/kvm
# Should show: crw-rw---- 1 root kvm

# Check KVM group membership
groups | grep kvm
# Should show: ... kvm ...

# If not in kvm group:
# sudo usermod -aG kvm $USER
# newgrp kvm
```

### 2. Ansible Collections

```bash
# Check if community.crypto is installed
ansible-galaxy collection list | grep community.crypto

# If not installed:
# ansible-galaxy collection install community.crypto
```

### 3. Directory Structure

```bash
# Verify all ansible files exist
ls ansible/ansible.cfg
ls ansible/inventory/hosts.yml
ls ansible/vars/vm-config.yml
ls ansible/playbooks/vm-provision.yml
ls ansible/playbooks/vm-stop.yml
ls ansible/playbooks/vm-destroy.yml
ls ansible/roles/snap_consumer/templates/user-data.j2
ls ansible/README.md

# Verify scripts
ls scripts/vm-health-check.sh
ls scripts/run-orchestration.sh
ls scripts/create-network.sh

# Verify VM directories (should be empty initially)
ls -d vm/images vm/disks vm/ssh
```

## Test 1: VM Provisioning

### Step 1: Provision the VM

```bash
cd ansible
ansible-playbook playbooks/vm-provision.yml
```

**Expected Output:**
- Task: "Download Ubuntu cloud image" - may take time on first run (~700MB)
- Task: "Create VM disk from cloud image" - creates qcow2 disk
- Task: "Generate cloud-init user-data" - creates cloud-init config
- Task: "Create cloud-init ISO" - creates cidata.iso
- Final message showing QEMU command to start VM

**Verify Files Created:**
```bash
ls -lh ../vm/images/ubuntu-24.04-cloudimg.img  # Base cloud image
ls -lh ../vm/disks/snap-consumer-vm.qcow2      # VM disk
ls -lh ../vm/disks/snap-consumer-vm-cidata.iso # Cloud-init ISO
ls -lh ../vm/ssh/id_ed25519                     # SSH private key
ls -lh ../vm/ssh/id_ed25519.pub                 # SSH public key
ls -lh ../vm/cloud-init-user-data               # Cloud-init config
```

**Success Criteria:**
- ✓ All tasks complete without errors
- ✓ All expected files created
- ✓ SSH key pair generated
- ✓ Cloud-init config generated

### Step 2: Manual VM Test (Optional)

```bash
# Start VM in foreground (for debugging)
cd ..
qemu-system-x86_64 \
  -name snap-consumer-vm \
  -m 2048 -smp 2 -enable-kvm \
  -drive file=vm/disks/snap-consumer-vm.qcow2,format=qcow2 \
  -drive file=vm/disks/snap-consumer-vm-cidata.iso,format=raw \
  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::9002-:9000 \
  -device virtio-net-pci,netdev=net0 \
  -nographic
```

**Expected Output:**
- Boot messages
- Cloud-init running
- "Snap consumer VM ready! Trigger server on port 9000"
- Login prompt: `snap-consumer-vm login:`

**In Another Terminal:**
```bash
# Wait for boot (~30-60 seconds)
sleep 60

# Check health endpoint
curl http://localhost:9002/health
# Should return: OK

# SSH into VM
ssh -p 2222 -i vm/ssh/id_ed25519 testrunner@localhost

# Inside VM, verify:
snap version           # Snap is installed
systemctl status snap-consumer.service  # Service is running
curl http://localhost:9000/health       # Trigger server responding
```

**To Stop VM:**
Press Ctrl+A, then X (QEMU monitor escape sequence)
Or from another terminal: `kill $(cat /tmp/snap-consumer-vm.pid)`

**Success Criteria:**
- ✓ VM boots successfully
- ✓ Cloud-init completes
- ✓ Health endpoint returns "OK"
- ✓ SSH access works
- ✓ Snapd is installed and running
- ✓ Trigger server service is active

## Test 2: Container Network Setup

```bash
# Create the network
./scripts/create-network.sh

# Verify network exists
podman network ls | grep podman-build-network

# Inspect network
podman network inspect podman-build-network
```

**Success Criteria:**
- ✓ Network created without errors
- ✓ Network appears in `podman network ls`
- ✓ Network driver is "bridge"

## Test 3: Orchestration Dry Run

```bash
# Start VM in background
qemu-system-x86_64 \
  -name snap-consumer-vm \
  -m 2048 -smp 2 -enable-kvm \
  -drive file=vm/disks/snap-consumer-vm.qcow2,format=qcow2 \
  -drive file=vm/disks/snap-consumer-vm-cidata.iso,format=raw \
  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::9002-:9000 \
  -device virtio-net-pci,netdev=net0 \
  -display none \
  -daemonize \
  -pidfile /tmp/snap-consumer-vm.pid

# Wait for VM to be ready
./scripts/vm-health-check.sh

# Start containers only (no build)
podman-compose up -d

# Verify all services are running
podman ps --format "table {{.Names}}\t{{.Status}}"

# Should show:
# - flatpak-registry (Up)
# - snap-registry (Up)
# - deb-registry (Up)
# - rpm-registry (Up)
# - consumer-arch (Up)
# - consumer-debian (Up)
# - consumer-redhat (Up)
# - builder (Up or Exited)

# Check health endpoints
curl http://localhost:9001/health  # consumer-arch
curl http://localhost:9002/health  # VM
curl http://localhost:9003/health  # consumer-debian
curl http://localhost:9004/health  # consumer-redhat

# Clean up
podman-compose down
kill $(cat /tmp/snap-consumer-vm.pid)
rm /tmp/snap-consumer-vm.pid
```

**Success Criteria:**
- ✓ All containers start successfully
- ✓ All health endpoints return "OK"
- ✓ VM accessible via localhost:9002
- ✓ Registries accessible on their ports

## Test 4: Full Orchestration

```bash
# Run the complete orchestration
./scripts/run-orchestration.sh
```

**Expected Flow:**
1. Prerequisites check passes
2. VM prerequisites check passes
3. Network creation (if needed)
4. VM starts and becomes healthy
5. Containers start
6. Builder runs and packages software
7. Builder triggers all consumers
8. Consumers install and test packages
9. Results are collected
10. All services shut down

**Expected Output:**
```
==========================================
Podman Container Orchestration
==========================================

Checking prerequisites...
Prerequisites OK

Step 1: Creating network...
[Network already exists or created]

Step 2: Starting snap consumer VM...
Starting snap-consumer-vm...
Waiting for VM to be ready...
Waiting for VM health check on localhost:9002...
VM is healthy!

Step 3: Launching all services...
[Container build output...]

Waiting for builder to complete (timeout: 10 minutes)...
[Builder logs showing build, package, and test phases...]

==========================================
Builder Results
==========================================

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

Stopping all services...
All tests passed!
```

**Success Criteria:**
- ✓ Script completes without errors (exit code 0)
- ✓ All 4 consumers report "PASS"
- ✓ All consumers output "All good"
- ✓ Builder exits with code 0
- ✓ All services shut down cleanly

## Test 5: Manual Trigger Test

```bash
# Start everything manually
./scripts/create-network.sh

# Start VM
qemu-system-x86_64 ... -daemonize -pidfile /tmp/snap-consumer-vm.pid
./scripts/vm-health-check.sh

# Start containers
podman-compose up -d

# Wait for everything to settle
sleep 10

# Manually trigger VM consumer
curl -X POST http://localhost:9002/trigger

# Should return: {"status": "triggered"}

# Wait for test to complete
sleep 30

# Check builder logs for result
podman logs builder | grep "consumer-ubuntu"

# Should show: consumer-ubuntu: PASS

# Clean up
podman-compose down
kill $(cat /tmp/snap-consumer-vm.pid)
```

**Success Criteria:**
- ✓ Trigger returns success status
- ✓ VM installs snap successfully
- ✓ VM runs test successfully
- ✓ VM reports result to builder
- ✓ Builder shows "consumer-ubuntu: PASS"

## Test 6: VM SSH Access

```bash
# With VM running
ssh -p 2222 -i vm/ssh/id_ed25519 testrunner@localhost

# Inside VM:
# Check snap service
sudo systemctl status snap-consumer.service
sudo journalctl -u snap-consumer.service -n 50

# Check snapd
snap version
snap list

# Check network connectivity
curl http://10.0.2.2:8081  # Should connect to snap-registry
curl http://10.0.2.2:9999  # Should connect to builder

# Check trigger server
curl http://localhost:9000/health  # Should return OK

# Exit VM
exit
```

**Success Criteria:**
- ✓ SSH connection works
- ✓ Service is running
- ✓ Network connectivity to host works
- ✓ Trigger server responds

## Test 7: Rebuild Test

```bash
# Stop everything
podman-compose down
cd ansible && ansible-playbook playbooks/vm-stop.yml && cd ..

# Destroy VM
cd ansible && ansible-playbook playbooks/vm-destroy.yml && cd ..

# Verify VM files removed
ls vm/disks/  # Should be empty or not found

# Reprovision
cd ansible && ansible-playbook playbooks/vm-provision.yml && cd ..

# Run orchestration again
./scripts/run-orchestration.sh
```

**Success Criteria:**
- ✓ Destroy removes all VM artifacts
- ✓ Reprovision recreates everything
- ✓ Orchestration runs successfully again

## Test 8: Error Handling

### Test VM Not Provisioned

```bash
# Destroy VM
cd ansible && ansible-playbook playbooks/vm-destroy.yml && cd ..

# Try to run orchestration without provisioning
./scripts/run-orchestration.sh

# Should error with:
# "ERROR: VM not provisioned. Run: cd ansible && ansible-playbook playbooks/vm-provision.yml"
```

### Test Missing Prerequisites

```bash
# Temporarily rename qemu
sudo mv /usr/bin/qemu-system-x86_64 /usr/bin/qemu-system-x86_64.bak

# Try to run
./scripts/run-orchestration.sh

# Should error with:
# "ERROR: qemu-system-x86_64 not found"

# Restore
sudo mv /usr/bin/qemu-system-x86_64.bak /usr/bin/qemu-system-x86_64
```

## Troubleshooting Guide

### VM Won't Start
```bash
# Check KVM access
ls -l /dev/kvm

# Check for conflicting VM
ps aux | grep qemu | grep snap-consumer

# Check PID file
cat /tmp/snap-consumer-vm.pid
kill -0 $(cat /tmp/snap-consumer-vm.pid)
```

### Health Check Fails
```bash
# Check VM is running
ps aux | grep qemu | grep snap-consumer

# Check port is listening
ss -tlnp | grep 9002

# Try direct curl with verbose
curl -v http://localhost:9002/health

# SSH into VM and check service
ssh -p 2222 -i vm/ssh/id_ed25519 testrunner@localhost
sudo systemctl status snap-consumer.service
sudo journalctl -u snap-consumer.service -n 100
```

### Snap Installation Fails
```bash
# SSH into VM
ssh -p 2222 -i vm/ssh/id_ed25519 testrunner@localhost

# Check snapd status
sudo systemctl status snapd
snap version

# Check connectivity to registry
curl -I http://10.0.2.2:8081

# Manual snap install test
curl -o /tmp/test.snap http://10.0.2.2:8081/snaps/access-keys_0.1.0_amd64.snap
sudo snap install --dangerous --devmode /tmp/test.snap
access-keys  # Should print "All good"
```

### Network Issues
```bash
# Check network exists
podman network ls | grep podman-build-network

# Verify port exposure
podman port snap-registry
podman port builder

# Test registry accessibility
curl http://localhost:8081  # snap-registry
curl http://localhost:9999  # builder
```

## Success Criteria Summary

All tests pass if:
- ✓ VM provisioning completes without errors
- ✓ VM boots and becomes healthy
- ✓ All health endpoints respond
- ✓ Full orchestration completes successfully
- ✓ All 4 consumers (including VM) report PASS
- ✓ SSH access to VM works
- ✓ VM can access registries via slirp gateway
- ✓ VM can report results to builder
- ✓ Cleanup works properly
- ✓ Rebuild works properly

## Performance Notes

Expected timings:
- First VM provision: ~5-10 minutes (includes cloud image download)
- Subsequent provisions: ~1-2 minutes (uses cached image)
- VM boot: ~30-60 seconds
- Full orchestration: ~3-5 minutes
- VM health check timeout: 120 seconds (configurable)

## Additional Resources

- `README.md` - Project overview
- `QUICKSTART.md` - Quick setup guide
- `ansible/README.md` - VM provisioning details
- `CLAUDE.md` - Development guidance
