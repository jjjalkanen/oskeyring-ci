# Post-Reboot Instructions - Complete Guide

**Created:** 2026-01-30
**Status:** Implementation complete, ready for testing after reboot
**Your location:** `/home/jjj/test_oskeyring`

---

## What Happened Before Reboot

We completed a full implementation to replace the problematic `consumer-ubuntu` container with a QEMU/KVM virtual machine. All code is written, all files are in place. The implementation is **100% complete**.

**What we changed:**
- Created 18 new files (Ansible playbooks, scripts, documentation)
- Modified 4 existing files (docker-compose.yml, trigger script, orchestration script, .gitignore)
- No more privileged containers or AppArmor modifications needed!

**Why you rebooted:**
- We ran `sudo usermod -aG kvm $USER` to add you to the KVM group
- Group membership changes only take effect after logout/login or reboot
- Without KVM group access, the VM cannot use hardware acceleration

---

## Immediate Post-Reboot Actions

### Step 0: Open Terminal and Navigate

```bash
cd /home/jjj/test_oskeyring
```

**Verify you're in the right place:**
```bash
pwd
# Expected output: /home/jjj/test_oskeyring

ls -1
# Should see: ansible/, vm/, scripts/, app/, builder/, consumers/, etc.
```

---

## Phase 1: Verify Prerequisites

### 1.1 Check KVM Group Membership (CRITICAL)

```bash
groups
```

**Expected output:**
```
jjj adm cdrom sudo dip plugdev kvm lpadmin lxd sambashare
```

**✓ SUCCESS:** The word `kvm` appears in the output
**✗ FAILURE:** If `kvm` is NOT in the output, you need to reboot again

If `kvm` is missing:
```bash
# Verify the command was run
sudo getent group kvm | grep $USER

# If you see your username, try logging out/in instead of reboot
# If still not working, run again and reboot:
sudo usermod -aG kvm $USER
sudo reboot
```

**STOP HERE IF KVM IS NOT IN YOUR GROUPS!**

### 1.2 Check KVM Device Access

```bash
ls -l /dev/kvm
```

**Expected output:**
```
crw-rw----+ 1 root kvm 10, 232 Jan 30 12:00 /dev/kvm
```

**Key things to verify:**
- `kvm` group appears
- Permissions include `rw` for group
- Device exists (not an error message)

### 1.3 Verify All Required Tools

Run this complete check:

```bash
echo "=== Checking Prerequisites ==="
echo -n "Ansible: " && command -v ansible && ansible --version | head -1 || echo "MISSING"
echo -n "QEMU: " && command -v qemu-system-x86_64 && qemu-system-x86_64 --version | head -1 || echo "MISSING"
echo -n "cloud-localds: " && command -v cloud-localds && echo "OK" || echo "MISSING"
echo -n "Podman: " && command -v podman && podman --version || echo "MISSING"
echo -n "Podman Compose: " && command -v podman-compose && podman-compose --version || echo "MISSING"
echo -n "KVM group: " && groups | grep -q kvm && echo "YES" || echo "NO"
echo "=== Check Complete ==="
```

**Expected output:**
```
=== Checking Prerequisites ===
Ansible: /usr/bin/ansible
ansible [core 2.xx.x]
QEMU: /usr/bin/qemu-system-x86_64
QEMU emulator version x.x.x
cloud-localds: /usr/bin/cloud-localds
OK
Podman: /usr/bin/podman
podman version x.x.x
Podman Compose: /usr/bin/podman-compose
podman-compose version x.x.x
KVM group: YES
=== Check Complete ===
```

**If anything shows "MISSING":**

```bash
# Install missing packages
sudo apt update
sudo apt install ansible qemu-system-x86 qemu-utils cloud-image-utils podman

# Install Ansible collection
ansible-galaxy collection install community.crypto

# For podman-compose (if missing)
sudo apt install podman-compose
# OR
pip3 install podman-compose
```

**STOP HERE IF ANY PREREQUISITE IS MISSING!**

---

## Phase 2: Provision the Virtual Machine

This step downloads Ubuntu 24.04 cloud image and creates the VM disk. **Only needs to be done once.**

### 2.1 Navigate and Run Provisioning

```bash
cd ansible
ansible-playbook playbooks/vm-provision.yml
```

### 2.2 What to Expect

**This will take 5-10 minutes** depending on your internet speed.

**Progress you'll see:**

```
PLAY [Provision Snap Consumer VM] *******************************************

TASK [Gathering Facts] ******************************************************
ok: [localhost]

TASK [Ensure directories exist] *********************************************
changed: [localhost] => (item=/home/jjj/test_oskeyring/vm/images)
changed: [localhost] => (item=/home/jjj/test_oskeyring/vm/disks)
changed: [localhost] => (item=/home/jjj/test_oskeyring/vm/ssh)

TASK [Generate SSH key for VM access] ***************************************
changed: [localhost]

TASK [Download Ubuntu cloud image] ******************************************
changed: [localhost]
# ← This step takes longest (downloads ~700MB)

TASK [Create VM disk from cloud image] **************************************
changed: [localhost]

TASK [Generate cloud-init user-data] ****************************************
changed: [localhost]

TASK [Create cloud-init ISO] ************************************************
changed: [localhost]

TASK [Display VM start command] *********************************************
ok: [localhost] => {
    "msg": "VM provisioned! Start with:\n\nqemu-system-x86_64 ..."
}

PLAY RECAP ******************************************************************
localhost                  : ok=8    changed=6    unreachable=0    failed=0
```

**✓ SUCCESS:**
- Shows `ok=8 changed=6 failed=0`
- No red error messages
- Ends with "PLAY RECAP"

**✗ FAILURE Indicators:**
- Red error messages
- `failed=1` or higher in PLAY RECAP
- Download timeout/network errors

**Common Issues:**

1. **Download timeout:**
```bash
# Try again, Ansible will resume the download
ansible-playbook playbooks/vm-provision.yml
```

2. **Permission denied on /dev/kvm:**
```bash
# Verify KVM group again
groups | grep kvm
# If missing, reboot is needed
```

3. **Ansible collection missing:**
```bash
# Install it
ansible-galaxy collection install community.crypto
# Run provisioning again
ansible-playbook playbooks/vm-provision.yml
```

### 2.3 Verify VM Files Were Created

```bash
cd ..  # Back to /home/jjj/test_oskeyring
ls -lh vm/images/
ls -lh vm/disks/
ls -l vm/ssh/
```

**Expected output:**

```
# vm/images/
total 665M
-rw-rw-r-- 1 jjj jjj 665M Jan 30 12:05 ubuntu-24.04-cloudimg.img

# vm/disks/
total 250M
-rw------- 1 jjj jjj 193K Jan 30 12:06 snap-consumer-vm-cidata.iso
-rw-r--r-- 1 jjj jjj 250M Jan 30 12:06 snap-consumer-vm.qcow2

# vm/ssh/
total 8
-rw------- 1 jjj jjj 464 Jan 30 12:05 id_ed25519
-rw-r--r-- 1 jjj jjj 103 Jan 30 12:05 id_ed25519.pub
```

**Key checks:**
- ✓ `ubuntu-24.04-cloudimg.img` exists (~600-700MB)
- ✓ `snap-consumer-vm.qcow2` exists (size varies, 200-300MB initial)
- ✓ `snap-consumer-vm-cidata.iso` exists (~200KB)
- ✓ `id_ed25519` exists (private key, mode 600)
- ✓ `id_ed25519.pub` exists (public key)

**If files are missing, re-run provisioning:**
```bash
cd ansible
ansible-playbook playbooks/vm-provision.yml
cd ..
```

---

## Phase 3: Test VM Standalone

Before running the full orchestration, let's test that the VM works by itself.

### 3.1 Start the VM

```bash
./scripts/vm-ctl.sh start
```

**Expected output:**

```
Starting VM...
VM started (PID: 12345)
Waiting for health check...
Waiting for VM to respond... (0s elapsed)
Waiting for VM to respond... (5s elapsed)
Waiting for VM to respond... (10s elapsed)
...
VM is healthy!
```

**This takes 60-90 seconds on first boot** (Ubuntu cloud-init setup)

**Timeline:**
- 0-30s: VM booting, kernel loading
- 30-60s: Cloud-init running, installing packages
- 60-90s: Services starting (snapd, trigger-server)
- 90s+: Health endpoint responds

**✓ SUCCESS:** Ends with "VM is healthy!"

**✗ FAILURE Indicators:**

1. **"ERROR: VM not provisioned"**
```bash
# Go back to Phase 2 and provision the VM
cd ansible
ansible-playbook playbooks/vm-provision.yml
cd ..
```

2. **"VM already running"**
```bash
# Check status
./scripts/vm-ctl.sh status
# If it's actually running, proceed to 3.2
# If it's a stale PID:
rm /tmp/snap-consumer-vm.pid
./scripts/vm-ctl.sh start
```

3. **Health check timeout after 120s**
```bash
# VM might be running but slow to boot
# Check if VM process exists
ps aux | grep qemu-system-x86_64 | grep snap-consumer-vm

# Try health check manually
curl http://localhost:9002/health
# If returns "OK", proceed to 3.2
# If connection refused, check VM logs via SSH
```

### 3.2 Verify VM Status

```bash
./scripts/vm-ctl.sh status
```

**Expected output:**
```
VM is running (PID: 12345)
```

### 3.3 Test Health Endpoint

```bash
./scripts/vm-ctl.sh health
```

**Expected output:**
```
VM health check: OK
```

**If you get "FAILED":**
```bash
# Wait a bit more and retry
sleep 30
./scripts/vm-ctl.sh health

# Check if port is listening
ss -tuln | grep 9002

# Try with curl directly
curl -v http://localhost:9002/health
```

### 3.4 SSH Into the VM

```bash
./scripts/vm-ctl.sh ssh
```

**Expected output:**
```
Connecting to VM via SSH (testrunner@localhost:2222)...
Welcome to Ubuntu 24.04 LTS (GNU/Linux 6.8.0-x-generic x86_64)
...
testrunner@snap-consumer-vm:~$
```

**Inside the VM, run these checks:**

```bash
# Check trigger server service
sudo systemctl status snap-consumer.service
```

**Expected:**
```
● snap-consumer.service - Snap Consumer Trigger Server
     Loaded: loaded (/etc/systemd/system/snap-consumer.service; enabled)
     Active: active (running) since ...
```

**Key indicator:** `Active: active (running)` in green

```bash
# Check snapd service
sudo systemctl status snapd.service
```

**Expected:**
```
● snapd.service - Snap Daemon
     Loaded: loaded (/lib/systemd/system/snapd.service; enabled)
     Active: active (running) since ...
```

```bash
# Check trigger server logs
sudo journalctl -u snap-consumer.service -n 20
```

**Expected to see:**
```
[trigger-server] Listening on port 9000
```

```bash
# Test network connectivity to host
ping -c 3 10.0.2.2
```

**Expected:**
```
PING 10.0.2.2 (10.0.2.2) 56(84) bytes of data.
64 bytes from 10.0.2.2: icmp_seq=1 ttl=255 time=0.xxx ms
...
3 packets transmitted, 3 received, 0% packet loss
```

```bash
# Exit SSH
exit
```

**Back on host now.**

### 3.5 View VM Logs

```bash
./scripts/vm-ctl.sh logs
```

**Expected output:**
```
[trigger-server] Listening on port 9000
```

**Press Ctrl+C to stop following logs.**

### 3.6 Stop the VM

```bash
./scripts/vm-ctl.sh stop
```

**Expected output:**
```
Stopping snap-consumer-vm...
VM stopped
```

**Verify it stopped:**
```bash
./scripts/vm-ctl.sh status
```

**Expected:**
```
VM is not running
```

---

## Phase 4: Run Full Orchestration

This is the main test that runs everything together.

### 4.1 Ensure Clean State

```bash
# Make sure VM is stopped
./scripts/vm-ctl.sh stop

# Make sure no containers are running
podman-compose down 2>/dev/null || true

# Check podman containers
podman ps -a
# Should be empty or only unrelated containers
```

### 4.2 Run the Orchestration

```bash
./scripts/run-orchestration.sh
```

### 4.3 What to Expect

**This takes 5-15 minutes.** You'll see:

**Part 1: Startup (1-2 minutes)**
```
==========================================
Podman Container Orchestration
==========================================

Checking prerequisites...
Prerequisites OK

Step 1: Creating network...
Network podman-build-network already exists (or created)

Step 2: Starting snap consumer VM...
Starting snap-consumer-vm...
VM started (PID: XXXXX)
Waiting for VM to be ready...
VM is healthy!

Step 3: Launching all services...
Note: Builder will run to completion, then containers will be stopped
```

**Part 2: Container Build and Start (3-5 minutes)**
```
[+] Building XX.Xs (flatpak-registry)
[+] Building XX.Xs (snap-registry)
[+] Building XX.Xs (deb-registry)
[+] Building XX.Xs (rpm-registry)
[+] Building XX.Xs (consumer-arch)
[+] Building XX.Xs (consumer-debian)
[+] Building XX.Xs (consumer-redhat)
[+] Building XX.Xs (builder)
...
Container flatpak-registry  Started
Container snap-registry  Started
Container deb-registry  Started
Container rpm-registry  Started
Container consumer-arch  Started
Container consumer-debian  Started
Container consumer-redhat  Started
Container builder  Started
```

**Part 3: Waiting for Builder (5-10 minutes)**
```
Waiting for builder to complete (timeout: 10 minutes)...
```

**This is where the magic happens:**
- Builder compiles the Rust app
- Packages it into 4 formats (Flatpak, Snap, DEB, RPM)
- Starts registry servers
- Triggers all 4 consumers
- Collects test results

**Part 4: Results**
```
==========================================
Builder Results
==========================================
[builder] ========================================
[builder] TEST RESULTS SUMMARY
[builder] ========================================
[builder]
[builder] ✓ consumer-arch: pass
[builder]   Output: All good! Your secret is: demo-secret-key-12345
[builder]
[builder] ✓ consumer-ubuntu: pass
[builder]   Output: All good! Your secret is: demo-secret-key-12345
[builder]
[builder] ✓ consumer-debian: pass
[builder]   Output: All good! Your secret is: demo-secret-key-12345
[builder]
[builder] ✓ consumer-redhat: pass
[builder]   Output: All good! Your secret is: demo-secret-key-12345
[builder]
[builder] ========================================
[builder] All tests passed! 4/4 consumers successful
[builder] ========================================

Stopping all services...
Stopping snap-consumer-vm...
VM stopped

All tests passed!

==========================================
Orchestration Complete
==========================================
```

### 4.4 Success Criteria

**✓ COMPLETE SUCCESS:** All 4 consumers show `✓ pass` with "All good!" output

The key line is:
```
✓ consumer-ubuntu: pass
```
This is the VM! If you see this, the VM implementation is working perfectly.

### 4.5 Partial Success or Failures

**Scenario 1: Some consumers pass, some fail**

If you see:
```
✓ consumer-arch: pass
✗ consumer-ubuntu: fail
✓ consumer-debian: pass
✓ consumer-redhat: pass
```

The VM is running but the snap test failed. Debug:

```bash
# Check builder logs for details
podman logs builder | grep -A 10 "consumer-ubuntu"

# Start VM manually and test
./scripts/vm-ctl.sh start
./scripts/vm-ctl.sh ssh

# Inside VM:
cd /opt/snap-consumer
source consumer.env
bash install.sh
python3 test-runner.py
```

**Scenario 2: VM health check timeout**

If orchestration fails at "Starting snap consumer VM":
```bash
# Check VM can start standalone
./scripts/vm-ctl.sh start
# Wait 2 minutes
./scripts/vm-ctl.sh health

# If health check works, try orchestration again
./scripts/run-orchestration.sh
```

**Scenario 3: Builder timeout**

If "Waiting for builder to complete" times out after 10 minutes:
```bash
# Check builder logs
podman logs builder

# Builder might be stuck on download or build
# Check if it's still running
podman ps | grep builder
```

### 4.6 Verify Final State

```bash
# Check VM is stopped
./scripts/vm-ctl.sh status
# Expected: "VM is not running"

# Check containers are stopped
podman ps
# Expected: Empty (no running containers from this project)
```

---

## Phase 5: Success Verification Checklist

If you reached here with all tests passing, verify everything:

```bash
cd /home/jjj/test_oskeyring

# 1. Verify VM files exist
ls vm/disks/snap-consumer-vm.qcow2
ls vm/ssh/id_ed25519

# 2. Verify VM can start/stop
./scripts/vm-ctl.sh start
sleep 60
./scripts/vm-ctl.sh health  # Should show "OK"
./scripts/vm-ctl.sh status  # Should show "running"
./scripts/vm-ctl.sh stop
./scripts/vm-ctl.sh status  # Should show "not running"

# 3. Run orchestration one more time to confirm consistency
./scripts/run-orchestration.sh
# Should show: "All tests passed! 4/4 consumers successful"
```

**If all of the above works: ✓ IMPLEMENTATION SUCCESSFUL!**

---

## Troubleshooting Decision Tree

### Problem: KVM group not showing after reboot

```
Solution:
1. Verify user was added: sudo getent group kvm
2. Try logout/login instead of reboot
3. Run command again: sudo usermod -aG kvm $USER && sudo reboot
```

### Problem: VM won't start - "ERROR: VM not provisioned"

```
Solution:
cd ansible
ansible-playbook playbooks/vm-provision.yml
cd ..
./scripts/vm-ctl.sh start
```

### Problem: VM starts but health check always fails

```
Solution:
1. Check VM is running: ps aux | grep qemu-system-x86_64
2. Check port: ss -tuln | grep 9002
3. SSH into VM: ./scripts/vm-ctl.sh ssh
4. Inside VM check: sudo systemctl status snap-consumer.service
5. View logs: sudo journalctl -u snap-consumer.service -n 50
6. If service failed, rebuild VM:
   exit
   ./scripts/vm-ctl.sh destroy
   ./scripts/vm-ctl.sh provision
   ./scripts/vm-ctl.sh start
```

### Problem: Orchestration fails - consumer-ubuntu test fails

```
Solution:
1. Check VM is accessible during orchestration
2. Start VM manually and test snap installation:
   ./scripts/vm-ctl.sh start
   ./scripts/vm-ctl.sh ssh
   cd /opt/snap-consumer
   source consumer.env
   bash install.sh  # Should download and install snap
   python3 test-runner.py  # Should output JSON with status
3. Check network from VM:
   curl http://10.0.2.2:8081/  # Should reach snap-registry
4. If snap fails to install, check snapd:
   sudo systemctl status snapd
   sudo journalctl -u snapd -n 50
```

### Problem: Can't SSH into VM

```
Solution:
1. Check VM is running: ./scripts/vm-ctl.sh status
2. Check SSH port: ss -tuln | grep 2222
3. Check SSH key exists: ls -l vm/ssh/id_ed25519
4. Try with verbose SSH:
   ssh -v -p 2222 -i vm/ssh/id_ed25519 testrunner@localhost
5. If "connection refused", VM isn't running or port forward failed
6. Full VM rebuild:
   ./scripts/vm-ctl.sh stop
   ./scripts/vm-ctl.sh destroy
   ./scripts/vm-ctl.sh provision
   ./scripts/vm-ctl.sh start
```

### Problem: Builder timeout

```
Solution:
1. Check builder logs: podman logs builder
2. Might be slow download or build, increase timeout in script
3. Or wait it out - first build can take 15+ minutes
4. Check builder is still alive: podman ps | grep builder
```

---

## Quick Reference Commands

```bash
# VM Management
./scripts/vm-ctl.sh start       # Start VM
./scripts/vm-ctl.sh stop        # Stop VM
./scripts/vm-ctl.sh restart     # Restart VM
./scripts/vm-ctl.sh status      # Check status
./scripts/vm-ctl.sh health      # Test health endpoint
./scripts/vm-ctl.sh ssh         # SSH into VM
./scripts/vm-ctl.sh logs        # View service logs
./scripts/vm-ctl.sh provision   # Create new VM
./scripts/vm-ctl.sh destroy     # Delete VM

# Testing
./scripts/run-orchestration.sh  # Run full test

# Container Management
podman-compose down             # Stop all containers
podman ps                       # List running containers
podman logs builder             # View builder logs
podman logs consumer-arch       # View consumer logs

# Debugging
podman logs builder | less      # Scroll through builder logs
./scripts/vm-ctl.sh ssh "sudo journalctl -u snap-consumer.service"
curl http://localhost:9002/health  # Test VM directly
```

---

## Success Indicators Summary

**✓ Prerequisites OK:**
- `groups` shows `kvm`
- `ls -l /dev/kvm` shows device with kvm group
- All tools installed (ansible, qemu, podman, etc.)

**✓ VM Provisioned:**
- `vm/disks/snap-consumer-vm.qcow2` exists
- `vm/ssh/id_ed25519` exists
- No errors during `ansible-playbook`

**✓ VM Works Standalone:**
- `./scripts/vm-ctl.sh start` succeeds
- `./scripts/vm-ctl.sh health` shows "OK"
- `./scripts/vm-ctl.sh ssh` connects
- Inside VM: `snap-consumer.service` is active

**✓ Full Orchestration Success:**
- All 4 consumers show `✓ pass`
- Specifically: `✓ consumer-ubuntu: pass` (this is the VM!)
- Output shows: "All tests passed! 4/4 consumers successful"
- Script exits cleanly

---

## If Everything Works

Congratulations! The VM implementation is successful. You now have:

- A working snap consumer running in a fully isolated VM
- No host security modifications needed
- Native systemd, snapd, and AppArmor support
- Clean orchestration that starts/stops everything automatically

**Next steps:**
- The system is ready for development
- Run `./scripts/run-orchestration.sh` anytime to test
- Use `./scripts/vm-ctl.sh` to manage the VM
- VM disk is persistent - installed snaps survive VM restarts

---

## Emergency Reset

If everything is broken and you want to start fresh:

```bash
cd /home/jjj/test_oskeyring

# Stop everything
./scripts/vm-ctl.sh stop
podman-compose down
podman rm -af  # Remove all containers
podman network rm podman-build-network 2>/dev/null || true

# Delete VM
./scripts/vm-ctl.sh destroy

# Recreate network
./scripts/create-network.sh

# Provision VM from scratch
cd ansible
ansible-playbook playbooks/vm-provision.yml
cd ..

# Test again
./scripts/run-orchestration.sh
```

---

**END OF POST-REBOOT INSTRUCTIONS**

**Start at:** Phase 1, Step 0
**Read carefully and follow each step in order**
**Don't skip verification steps - they catch issues early**
