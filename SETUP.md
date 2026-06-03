# Setup Guide

Prerequisites and first-run setup for the oskeyring CI system on Ubuntu.

## 1. System Packages

```bash
sudo apt install podman podman-compose qemu-system-x86 cloud-image-utils fuse ansible
```

- `podman` / `podman-compose` — container orchestration
- `qemu-system-x86` — QEMU/KVM VMs for the Snap and Debian consumers
- `cloud-image-utils` — `cloud-localds` for cloud-init ISO generation
- `fuse` — required by Flatpak's bubblewrap inside the Arch consumer container
- `ansible` — VM provisioning playbooks

## 2. Ansible Collection

```bash
ansible-galaxy collection install community.crypto
```

Used by the VM provisioning playbooks for SSH key generation.

## 3. KVM Access

```bash
sudo usermod -aG kvm $USER
```

Log out and back in for the group change to take effect. Verify with:

```bash
ls -la /dev/kvm
# Should show your group has rw access
```

## 4. Rust Toolchain

The `access-keys` canary app and `firefox-credential-server` are Rust binaries built on the host:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

## 5. Firefox Build Dependencies

Firefox is compiled from source in `firefox/`. Bootstrap the build environment:

```bash
cd firefox
./mach bootstrap
cd ..
```

This installs compilers, libraries, and a pinned version of `buildcache`. It can take a while on a fresh system.

## 6. RHEL 9 onnxruntime (for consumer-redhat)

The RPM consumer needs a RHEL 9-compatible `libonnxruntime.so` that can't be built on the host. This builds it inside a UBI9 container:

```bash
./scripts/build-onnxruntime-rhel9.sh
```

Output lands in `dist/onnxruntime-rhel9/`. Only needs to be re-run if the onnxruntime revision changes.

## 7. Provision VMs

Two consumers run in QEMU VMs (not containers) because they need a real kernel for snapd/AppArmor and systemd credential encryption:

```bash
cd ansible
ansible-playbook playbooks/vm-provision.yml       # Snap consumer (Ubuntu VM)
ansible-playbook playbooks/deb-vm-provision.yml   # Debian consumer (Debian VM)
cd ..
```

### Bake VMs (optional, recommended)

After provisioning, start the VMs, wait for them to become healthy, then bake a snapshot so subsequent runs skip cloud-init:

```bash
# Start the VMs (bake requires them to be running)
VM_TYPE=snap ./scripts/vm-ctl.sh start
VM_TYPE=deb ./scripts/vm-ctl.sh start

# Bake snapshots
cd ansible
ansible-playbook playbooks/vm-bake.yml
ansible-playbook playbooks/deb-vm-bake.yml
cd ..
```

With baked images, `run-orchestration.sh` creates a lightweight overlay disk that is discarded after each run, giving a clean state every time.

## 8. Run the Orchestration

```bash
./scripts/run-orchestration.sh
```

First run will be slow (Firefox build from source + container image builds). Subsequent `--no-build` runs reuse existing Firefox artifacts and are much faster.

### Running a Subset of Consumers

If you only want to test specific platforms (e.g., skip the long RHEL9 build):

```bash
./scripts/run-orchestration.sh --consumer consumer-arch --consumer consumer-debian
```

Valid consumer names: `consumer-arch`, `consumer-ubuntu`, `consumer-debian`, `consumer-redhat`.
