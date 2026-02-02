# Post-Reboot Testing Checklist

**Location:** `/home/jjj/test_oskeyring`

---

## Pre-Flight Checks

- [ ] Verify KVM group: `groups | grep kvm` → Must show "kvm"
- [ ] Check KVM device: `ls -l /dev/kvm` → Must exist with kvm group
- [ ] Verify tools: Run all commands below, all must return paths:
  - [ ] `command -v ansible`
  - [ ] `command -v qemu-system-x86_64`
  - [ ] `command -v cloud-localds`
  - [ ] `command -v podman`
  - [ ] `command -v podman-compose`

**If any checks fail:** See POST_REBOOT_INSTRUCTIONS.md Phase 1

---

## VM Provisioning

- [ ] Navigate: `cd /home/jjj/test_oskeyring`
- [ ] Provision: `cd ansible && ansible-playbook playbooks/vm-provision.yml && cd ..`
  - **Takes:** 5-10 minutes (downloads ~700MB)
  - **Success:** `failed=0` in PLAY RECAP
- [ ] Verify files created:
  - [ ] `ls vm/images/ubuntu-24.04-cloudimg.img`
  - [ ] `ls vm/disks/snap-consumer-vm.qcow2`
  - [ ] `ls vm/ssh/id_ed25519`

**If provisioning fails:** See POST_REBOOT_INSTRUCTIONS.md Phase 2

---

## VM Standalone Test

- [ ] Start: `./scripts/vm-ctl.sh start`
  - **Takes:** 60-90 seconds
  - **Success:** "VM is healthy!"
- [ ] Status: `./scripts/vm-ctl.sh status` → "VM is running"
- [ ] Health: `./scripts/vm-ctl.sh health` → "OK"
- [ ] SSH: `./scripts/vm-ctl.sh ssh`
  - [ ] Inside VM: `sudo systemctl status snap-consumer.service` → "active (running)"
  - [ ] Inside VM: `sudo systemctl status snapd.service` → "active (running)"
  - [ ] Exit: `exit`
- [ ] Logs: `./scripts/vm-ctl.sh logs` → See "Listening on port 9000" (Ctrl+C to exit)
- [ ] Stop: `./scripts/vm-ctl.sh stop` → "VM stopped"

**If VM test fails:** See POST_REBOOT_INSTRUCTIONS.md Phase 3

---

## Full Orchestration

- [ ] Clean state: `./scripts/vm-ctl.sh stop && podman-compose down`
- [ ] Run: `./scripts/run-orchestration.sh`
  - **Takes:** 5-15 minutes
  - **Success criteria:**
    - [ ] "VM is healthy!" appears
    - [ ] All containers start
    - [ ] Builder completes
    - [ ] `✓ consumer-arch: pass`
    - [ ] `✓ consumer-ubuntu: pass` ← **THE VM!**
    - [ ] `✓ consumer-debian: pass`
    - [ ] `✓ consumer-redhat: pass`
    - [ ] "All tests passed! 4/4 consumers successful"
- [ ] Verify cleanup: `./scripts/vm-ctl.sh status` → "not running"

**If orchestration fails:** See POST_REBOOT_INSTRUCTIONS.md Phase 4

---

## Final Verification

- [ ] Run orchestration again: `./scripts/run-orchestration.sh`
  - [ ] All 4 consumers pass again
  - [ ] Consistent results

---

## Success! ✓

**You're done if:**
- All checkboxes above are checked
- Orchestration shows "All tests passed! 4/4 consumers successful"
- consumer-ubuntu (VM) shows `✓ pass`

**What you have:**
- Working snap consumer in isolated VM
- No host security modifications
- Full systemd/snapd/AppArmor support
- Automated testing pipeline

---

## Quick Commands Reference

```bash
# Most common commands you'll use:

# Run full test
./scripts/run-orchestration.sh

# Manage VM
./scripts/vm-ctl.sh start|stop|status|health|ssh|logs

# Debug
podman logs builder
./scripts/vm-ctl.sh ssh "sudo journalctl -u snap-consumer.service"

# Full reset
./scripts/vm-ctl.sh destroy && ./scripts/vm-ctl.sh provision
```

---

## If Something Fails

1. **Read error messages carefully**
2. **Check POST_REBOOT_INSTRUCTIONS.md** for detailed troubleshooting
3. **Try emergency reset:**
   ```bash
   ./scripts/vm-ctl.sh stop
   podman-compose down
   ./scripts/vm-ctl.sh destroy
   cd ansible && ansible-playbook playbooks/vm-provision.yml && cd ..
   ./scripts/run-orchestration.sh
   ```

---

**Detailed Instructions:** POST_REBOOT_INSTRUCTIONS.md
**Quick Summary:** RESUME_HERE.txt
**Status & Context:** WHERE_WE_ARE.md
