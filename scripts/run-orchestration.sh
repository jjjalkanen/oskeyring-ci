#!/bin/bash
set -e

VM_NAME="snap-consumer-vm"
VM_PID_FILE="/tmp/${VM_NAME}.pid"

echo "=========================================="
echo "Podman Container Orchestration"
echo "=========================================="
echo ""

# Check prerequisites
check_prerequisites() {
    local failed=0

    echo "Checking prerequisites..."

    # Check for /dev/fuse (required for flatpak)
    if [ ! -e /dev/fuse ]; then
        echo "ERROR: /dev/fuse not found. Install fuse: sudo apt install fuse"
        failed=1
    fi

    # Check for podman
    if ! command -v podman &>/dev/null; then
        echo "ERROR: podman not found"
        failed=1
    fi

    # Check for podman-compose
    if ! command -v podman-compose &>/dev/null; then
        echo "ERROR: podman-compose not found"
        failed=1
    fi

    # Check for qemu-system-x86_64
    if ! command -v qemu-system-x86_64 &>/dev/null; then
        echo "ERROR: qemu-system-x86_64 not found. Install: sudo apt install qemu-system-x86"
        failed=1
    fi

    if [ $failed -ne 0 ]; then
        echo "Prerequisites check failed!"
        exit 1
    fi

    echo "Prerequisites OK"
    echo ""
}

# Check VM is provisioned
check_vm_prerequisites() {
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    if [ ! -f "$SCRIPT_DIR/../vm/disks/${VM_NAME}.qcow2" ]; then
        echo "ERROR: VM not provisioned. Run:"
        echo "  cd ansible && ansible-playbook playbooks/vm-provision.yml"
        exit 1
    fi
}

# Reset VM state function
reset_vm_state() {
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    VM_DIR="$SCRIPT_DIR/../vm"
    BAKED_DISK="$VM_DIR/disks/${VM_NAME}-baked.qcow2"
    OVERLAY_DISK="$VM_DIR/disks/${VM_NAME}-overlay.qcow2"

    if [ -f "$BAKED_DISK" ]; then
        echo "Resetting VM to clean state..."
        rm -f "$OVERLAY_DISK"
        qemu-img create -f qcow2 -b "$(basename "$BAKED_DISK")" -F qcow2 "$OVERLAY_DISK" >/dev/null 2>&1
        echo "VM state reset (using overlay)"
    fi
}

# Start VM function
start_vm() {
    echo "Starting snap-consumer-vm..."

    if [ -f "$VM_PID_FILE" ] && kill -0 $(cat "$VM_PID_FILE") 2>/dev/null; then
        echo "VM already running"
        return 0
    fi

    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    VM_DIR="$SCRIPT_DIR/../vm"
    BAKED_DISK="$VM_DIR/disks/${VM_NAME}-baked.qcow2"
    OVERLAY_DISK="$VM_DIR/disks/${VM_NAME}-overlay.qcow2"
    BASE_DISK="$VM_DIR/disks/${VM_NAME}.qcow2"

    # Use overlay if baked image exists, otherwise use base
    if [ -f "$BAKED_DISK" ]; then
        DISK_IMAGE="$OVERLAY_DISK"
        echo "Using baked image with overlay (fast boot)..."
    else
        DISK_IMAGE="$BASE_DISK"
        echo "Using base image (cloud-init will run)..."
    fi

    mkdir -p "$VM_DIR/logs"
    qemu-system-x86_64 \
        -name "$VM_NAME" \
        -m 2048 \
        -smp 2 \
        -enable-kvm \
        -drive file="$DISK_IMAGE",format=qcow2 \
        -drive file="$VM_DIR/disks/${VM_NAME}-cidata.iso",format=raw \
        -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::9002-:9000 \
        -device virtio-net-pci,netdev=net0 \
        -serial file:"$VM_DIR/logs/console.log" \
        -display none \
        -daemonize \
        -pidfile "$VM_PID_FILE"

    echo "Waiting for VM to be ready..."
    ./scripts/vm-health-check.sh
}

# Stop VM function
stop_vm() {
    echo "Stopping snap-consumer-vm..."
    if [ -f "$VM_PID_FILE" ]; then
        kill $(cat "$VM_PID_FILE") 2>/dev/null || true
        rm -f "$VM_PID_FILE"
    fi
}

# Cleanup handler
TIMEOUT_MINUTES=120
CLEANUP_DONE=false

cleanup() {
    if [ "$CLEANUP_DONE" = true ]; then return; fi
    CLEANUP_DONE=true
    echo "Cleaning up..."
    podman-compose down --timeout 10 2>/dev/null || {
        podman stop -a -t 5 2>/dev/null || true
        podman rm -a -f 2>/dev/null || true
    }
    stop_vm
}

trap cleanup EXIT INT TERM

# Run prerequisite checks
check_prerequisites
check_vm_prerequisites

# Step 1: Create network
echo "Step 1: Creating network..."
./scripts/create-network.sh
echo ""

# Step 2: Start VM
echo "Step 2: Starting snap consumer VM..."
reset_vm_state
start_vm
echo ""

# Step 2.5: Update scripts in VM
echo "Step 2.5: Updating scripts in VM..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Wait for SSH to be ready (max 60 seconds)
echo "Waiting for SSH to be ready on port 2222..."
for i in {1..60}; do
    if ssh -i "$SCRIPT_DIR/../vm/ssh/id_ed25519" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=2 \
        -p 2222 \
        testrunner@localhost "exit" 2>/dev/null; then
        echo "SSH is ready"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "WARNING: SSH not ready after 60 seconds, skipping script update"
        echo ""
        # Continue without updating (VM will use embedded script)
        # Don't exit - this is not critical
    else
        sleep 1
    fi
done

# Copy and update scripts if SSH is ready
if ssh -i "$SCRIPT_DIR/../vm/ssh/id_ed25519" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=2 \
    -p 2222 \
    testrunner@localhost "exit" 2>/dev/null; then

    # Push test-runner.py
    scp -i "$SCRIPT_DIR/../vm/ssh/id_ed25519" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -P 2222 \
        "$SCRIPT_DIR/../consumers/trigger-server/test-runner.py" \
        testrunner@localhost:/tmp/test-runner.py 2>&1 | grep -v "Warning: Permanently added" || true

    ssh -i "$SCRIPT_DIR/../vm/ssh/id_ed25519" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p 2222 \
        testrunner@localhost \
        "sudo mv /tmp/test-runner.py /opt/snap-consumer/test-runner.py && sudo chmod +x /opt/snap-consumer/test-runner.py" 2>&1 | grep -v "Warning: Permanently added" || true

    # Push server.py
    scp -i "$SCRIPT_DIR/../vm/ssh/id_ed25519" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -P 2222 \
        "$SCRIPT_DIR/../consumers/trigger-server/server.py" \
        testrunner@localhost:/tmp/server.py 2>&1 | grep -v "Warning: Permanently added" || true

    ssh -i "$SCRIPT_DIR/../vm/ssh/id_ed25519" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p 2222 \
        testrunner@localhost \
        "sudo mv /tmp/server.py /opt/snap-consumer/server.py && sudo chmod +x /opt/snap-consumer/server.py" 2>&1 | grep -v "Warning: Permanently added" || true

    # Push upgrade.sh
    scp -i "$SCRIPT_DIR/../vm/ssh/id_ed25519" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -P 2222 \
        "$SCRIPT_DIR/../consumers/ubuntu-snap/upgrade.sh" \
        testrunner@localhost:/tmp/upgrade.sh 2>&1 | grep -v "Warning: Permanently added" || true

    ssh -i "$SCRIPT_DIR/../vm/ssh/id_ed25519" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p 2222 \
        testrunner@localhost \
        "sudo mv /tmp/upgrade.sh /opt/snap-consumer/upgrade.sh && sudo chmod +x /opt/snap-consumer/upgrade.sh" 2>&1 | grep -v "Warning: Permanently added" || true

    # Configure sudoers for testrunner
    ssh -i "$SCRIPT_DIR/../vm/ssh/id_ed25519" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p 2222 \
        testrunner@localhost \
        "echo 'testrunner ALL=(ALL) NOPASSWD: /opt/snap-consumer/upgrade.sh' | sudo tee /etc/sudoers.d/testrunner" 2>&1 | grep -v "Warning: Permanently added" || true

    # Set CONSUMER_DIR env in snap-consumer.service
    ssh -i "$SCRIPT_DIR/../vm/ssh/id_ed25519" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p 2222 \
        testrunner@localhost \
        "sudo mkdir -p /etc/systemd/system/snap-consumer.service.d && printf '[Service]\nEnvironment=CONSUMER_DIR=/opt/snap-consumer\n' | sudo tee /etc/systemd/system/snap-consumer.service.d/override.conf && sudo systemctl daemon-reload && sudo systemctl restart snap-consumer" 2>&1 | grep -v "Warning: Permanently added" || true

    # Clear snap data from previous test runs
    echo "Clearing snap data from previous runs..."
    ssh -i "$SCRIPT_DIR/../vm/ssh/id_ed25519" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p 2222 \
        testrunner@localhost \
        "sudo rm -rf /var/snap/access-keys/current/* 2>/dev/null || true" 2>&1 | grep -v "Warning: Permanently added" || true

    echo "Scripts updated successfully"
fi
echo ""

# Step 3: Build images
echo "Step 3: Building container images..."
echo ""

podman-compose build

# Step 4: Start services
echo ""
echo "Step 4: Starting all services..."
echo "Note: Builder will run to completion, then containers will be stopped"
echo ""

podman-compose up -d

# Give services a moment to start up
echo "Waiting for services to initialize..."
sleep 5

# Wait for builder to complete
echo "Waiting for builder to complete (timeout: ${TIMEOUT_MINUTES} minutes)..."
START_TIME=$(date +%s)
while podman ps --format '{{.Names}}' | grep -q '^builder$'; do
    ELAPSED=$(($(date +%s) - START_TIME))
    if [ $ELAPSED -ge $((TIMEOUT_MINUTES * 60)) ]; then
        echo "ERROR: Timeout after ${TIMEOUT_MINUTES} minutes"
        exit 1
    fi
    sleep 2
done

# Show builder logs for results
echo ""
echo "=========================================="
echo "Builder Results"
echo "=========================================="
podman logs builder 2>&1 | grep -A 50 "TEST RESULTS SUMMARY" || podman logs builder | tail -30

# Get builder exit code
BUILDER_EXIT=$(podman inspect builder --format '{{.State.ExitCode}}')

# Stop all services
echo ""
echo "Stopping all services..."
podman-compose down

# Return builder's exit code
if [ "$BUILDER_EXIT" -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed (exit code: $BUILDER_EXIT)"
    exit $BUILDER_EXIT
fi

echo ""
echo "=========================================="
echo "Orchestration Complete"
echo "=========================================="
