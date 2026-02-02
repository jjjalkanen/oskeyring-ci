# Current Status - VM Implementation

**Date:** 2026-01-30
**Status:** Implementation complete, ready for testing

## What We Just Did

We successfully implemented a plan to replace the problematic `consumer-ubuntu` container with a QEMU/KVM virtual machine. The implementation is **complete** - all code has been written and all files are in place.

### Implementation Summary

- ✅ Created Ansible playbooks for VM provisioning and lifecycle management
- ✅ Created cloud-init configuration for automatic VM setup
- ✅ Removed `consumer-ubuntu` container from docker-compose.yml
- ✅ Updated builder trigger script to use VM via host port forwarding
- ✅ Updated orchestration script to manage VM lifecycle
- ✅ Created helper scripts (`vm-ctl.sh`, `vm-health-check.sh`)
- ✅ Created comprehensive documentation (5 docs)
- ✅ Updated .gitignore for VM artifacts

**Total changes:** 18 new files, 4 files modified

---

## IMPORTANT: Before Testing

### ⚠️ REBOOT REQUIRED ⚠️

You need to **reboot your system** to activate the KVM group membership changes:

```bash
# This command was already run:
sudo usermod -aG kvm $USER

# But group changes require logout/login or reboot
# REBOOT NOW before proceeding
sudo reboot
```

After reboot, verify:
```bash
# Check you're in kvm group
groups | grep kvm
# Should show "kvm" in the output

# Check KVM device access
ls -l /dev/kvm
# Should show: crw-rw----+ 1 root kvm
```

---

## Next Steps (After Reboot)

### Step 1: Verify Prerequisites

```bash
cd /home/jjj/test_oskeyring

# Check all tools are installed
command -v ansible && echo "✓ Ansible"
command -v qemu-system-x86_64 && echo "✓ QEMU"
command -v cloud-localds && echo "✓ cloud-image-utils"
command -v podman && echo "✓ Podman"
command -v podman-compose && echo "✓ Podman Compose"

# Verify KVM group membership (CRITICAL)
groups | grep kvm && echo "✓ KVM group" || echo "✗ REBOOT REQUIRED"

# Check KVM device
ls -l /dev/kvm
```

If any tools are missing:
```bash
sudo apt install ansible qemu-system-x86 qemu-utils cloud-image-utils
ansible-galaxy collection install community.crypto
```

### Step 2: Provision the VM

```bash
cd ansible
ansible-playbook playbooks/vm-provision.yml
cd ..
```

**What this does:**
- Downloads Ubuntu 24.04 cloud image (~700MB, may take a few minutes)
- Creates a 20GB VM disk image (sparse file, doesn't use 20GB)
- Generates SSH keypair in `vm/ssh/`
- Creates cloud-init ISO with VM configuration
- Prepares everything needed to run the VM

**Expected output:**
- Should complete without errors
- Will show a QEMU command at the end (informational)

**Files created:**
- `vm/images/ubuntu-24.04-cloudimg.img` - Base cloud image
- `vm/disks/snap-consumer-vm.qcow2` - VM disk
- `vm/disks/snap-consumer-vm-cidata.iso` - Cloud-init ISO
- `vm/ssh/id_ed25519` - SSH private key
- `vm/ssh/id_ed25519.pub` - SSH public key

### Step 3: Test VM Standalone (Optional but Recommended)

Before running the full orchestration, test the VM by itself:

```bash
# Start VM
./scripts/vm-ctl.sh start

# Check status
./scripts/vm-ctl.sh status
# Expected: "VM is running (PID: XXXX)"

# Check health endpoint (may take 60-90 seconds after start)
./scripts/vm-ctl.sh health
# Expected: "VM health check: OK"

# SSH into the VM
./scripts/vm-ctl.sh ssh
# Inside VM, check services:
sudo systemctl status snap-consumer.service
sudo systemctl status snapd.service
# Both should show "active (running)"
# Type 'exit' to disconnect

# View service logs
./scripts/vm-ctl.sh logs
# Should show trigger server listening on port 9000
# Press Ctrl+C to stop following logs

# Stop VM
./scripts/vm-ctl.sh stop
# Expected: "VM stopped"
```

### Step 4: Run Full Orchestration

This is the main test - it will:
1. Check prerequisites (including VM provisioning)
2. Create podman network
3. Start the VM
4. Start all containers (registries + consumers + builder)
5. Build packages in 4 formats
6. Trigger all 4 consumers (including the VM)
7. Collect test results
8. Stop everything automatically

```bash
./scripts/run-orchestration.sh
```

**Expected output:**
```
========================================
Podman Container Orchestration
========================================

Checking prerequisites...
Prerequisites OK

Step 1: Creating network...
[Network creation messages]

Step 2: Starting snap consumer VM...
Starting snap-consumer-vm...
VM started (PID: XXXX)
Waiting for VM to be ready...
VM is healthy!

Step 3: Launching all services...
[Container startup messages]

[Build process messages]

[Test results]
✓ consumer-arch: pass
✓ consumer-ubuntu: pass  ← This is the VM!
✓ consumer-debian: pass
✓ consumer-redhat: pass

All tests passed!
```

---

## VM Control Script Reference (`vm-ctl.sh`)

The `vm-ctl.sh` script provides easy VM management:

### Basic Commands

```bash
# Start VM (boots in background, waits for health check)
./scripts/vm-ctl.sh start

# Stop VM (graceful shutdown)
./scripts/vm-ctl.sh stop

# Restart VM
./scripts/vm-ctl.sh restart

# Check if VM is running
./scripts/vm-ctl.sh status

# Check health endpoint (http://localhost:9002/health)
./scripts/vm-ctl.sh health
```

### Access and Debugging

```bash
# SSH into VM as testrunner user
./scripts/vm-ctl.sh ssh

# Run a command via SSH
./scripts/vm-ctl.sh ssh "sudo systemctl status snapd"

# View snap consumer service logs (follows in real-time)
./scripts/vm-ctl.sh logs
```

### VM Lifecycle

```bash
# Provision a new VM (only needed once, or after destroy)
./scripts/vm-ctl.sh provision

# Destroy VM (deletes disk, requires confirmation)
./scripts/vm-ctl.sh destroy

# Full rebuild
./scripts/vm-ctl.sh destroy
./scripts/vm-ctl.sh provision
```

### Useful SSH Commands

Once inside the VM (`./scripts/vm-ctl.sh ssh`):

```bash
# Check trigger server status
sudo systemctl status snap-consumer.service

# View trigger server logs
sudo journalctl -u snap-consumer.service -n 50

# Check snapd status
sudo systemctl status snapd.service

# List installed snaps
snap list

# Test network connectivity to host
ping -c 3 10.0.2.2
curl http://10.0.2.2:8081/  # Snap registry
curl http://10.0.2.2:9999/health  # Builder (when running)

# Manually run the test
cd /opt/snap-consumer
source consumer.env
bash install.sh
python3 test-runner.py
```

---

## Troubleshooting

### VM Won't Start

```bash
# Check KVM group membership
groups | grep kvm

# Check KVM device
ls -l /dev/kvm
# Should show: crw-rw----+ 1 root kvm

# Check if VM is already running
./scripts/vm-ctl.sh status

# Check for stale PID file
ls -l /tmp/snap-consumer-vm.pid
```

### VM Health Check Fails

```bash
# Wait longer - first boot can take 90+ seconds
sleep 60 && ./scripts/vm-ctl.sh health

# Check if VM is running
./scripts/vm-ctl.sh status

# Try SSH (may work even if health check doesn't)
./scripts/vm-ctl.sh ssh

# Inside VM, check service
sudo systemctl status snap-consumer.service
sudo journalctl -u snap-consumer.service -n 50
```

### Orchestration Fails

```bash
# Check VM is provisioned
ls -l vm/disks/snap-consumer-vm.qcow2

# Check network exists
podman network ls | grep podman-build-network

# Run with more verbose output
bash -x ./scripts/run-orchestration.sh
```

### Full Reset

```bash
# Stop everything
./scripts/vm-ctl.sh stop
podman-compose down

# Rebuild VM
./scripts/vm-ctl.sh destroy
./scripts/vm-ctl.sh provision

# Try again
./scripts/run-orchestration.sh
```

---

## Architecture Quick Reference

```
Host Machine
│
├── Podman Network (podman-build-network)
│   ├── builder:9999 (exposed on host)
│   ├── snap-registry:8081 (exposed on host)
│   ├── flatpak-registry:8080
│   ├── deb-registry:8082
│   ├── rpm-registry:8083
│   ├── consumer-arch:9000
│   ├── consumer-debian:9000
│   └── consumer-redhat:9000
│
└── QEMU VM (user-mode networking, port forwarding)
    ├── Host port 9002 → VM port 9000 (trigger server)
    ├── Host port 2222 → VM port 22 (SSH)
    └── VM sees host as 10.0.2.2 (slirp gateway)
        └── snap-consumer-vm (Ubuntu 24.04)
            ├── snapd (native, full support)
            ├── AppArmor (native, full support)
            ├── systemd (native, full support)
            └── trigger-server.py on port 9000
```

**Network flow:**
1. Builder triggers: `host.containers.internal:9002` → VM:9000
2. VM downloads snap: `10.0.2.2:8081` → snap-registry
3. VM reports results: `10.0.2.2:9999` → builder

---

## Documentation Files

All documentation is in place:

- **WHERE_WE_ARE.md** (this file) - Current status and next steps
- **QUICKSTART_VM.md** - Quick start guide
- **VM_IMPLEMENTATION.md** - Technical architecture details
- **IMPLEMENTATION_CHECKLIST.md** - Step-by-step verification
- **IMPLEMENTATION_COMPLETE.md** - Summary of changes
- **ansible/README.md** - Ansible playbook documentation

---

## Summary: What To Do Next

1. **REBOOT** your system (if you haven't already)
2. **Verify** KVM group membership: `groups | grep kvm`
3. **Provision** VM: `cd ansible && ansible-playbook playbooks/vm-provision.yml && cd ..`
4. **Test** VM standalone: `./scripts/vm-ctl.sh start && ./scripts/vm-ctl.sh health`
5. **Run** full test: `./scripts/run-orchestration.sh`

Expected result: All 4 consumers pass (arch, ubuntu/VM, debian, redhat)

---

**Implementation Status:** ✅ Complete
**Testing Status:** ⏳ Pending (blocked on reboot + VM provisioning)
**Next Action:** REBOOT, then provision VM with ansible
