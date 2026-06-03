#!/bin/bash
# VM control script - supports snap and deb consumer VMs
# Usage: VM_TYPE=snap|deb ./vm-ctl.sh <command>

set -e

# Select VM type (default: snap for backward compatibility)
VM_TYPE="${VM_TYPE:-snap}"

case "$VM_TYPE" in
    snap)
        VM_NAME="snap-consumer-vm"
        SSH_PORT=2222
        TRIGGER_PORT=9002
        SSH_USER=testrunner
        PROVISION_PLAYBOOK="playbooks/vm-provision.yml"
        BAKE_PLAYBOOK="playbooks/vm-bake.yml"
        DESTROY_PLAYBOOK="playbooks/vm-destroy.yml"
        SERVICE_NAME="snap-consumer"
        ;;
    deb)
        VM_NAME="deb-consumer-vm"
        SSH_PORT=2223
        TRIGGER_PORT=9003
        SSH_USER=consumer
        PROVISION_PLAYBOOK="playbooks/deb-vm-provision.yml"
        BAKE_PLAYBOOK="playbooks/deb-vm-bake.yml"
        DESTROY_PLAYBOOK="playbooks/deb-vm-destroy.yml"
        SERVICE_NAME="trigger-server"
        ;;
    *)
        echo "ERROR: Unknown VM_TYPE '$VM_TYPE'. Use 'snap' or 'deb'."
        exit 1
        ;;
esac

VM_PID_FILE="/tmp/${VM_NAME}.pid"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VM_DIR="$SCRIPT_DIR/../vm"
ANSIBLE_DIR="$SCRIPT_DIR/../ansible"
OVERLAY_DISK="$VM_DIR/disks/${VM_NAME}-overlay.qcow2"
BAKED_DISK="$VM_DIR/disks/${VM_NAME}-baked.qcow2"
BASE_DISK="$VM_DIR/disks/${VM_NAME}.qcow2"

show_usage() {
    cat << EOF
Usage: VM_TYPE=${VM_TYPE} $0 <command>

VM_TYPE: snap (default) or deb

Commands:
    start          Start the VM
    stop           Stop the VM
    restart        Restart the VM
    status         Check if VM is running
    health         Check VM health endpoint
    ssh            SSH into the VM
    logs           View VM service logs
    console        Attach to VM console (use Ctrl-A X to exit)
    provision      Provision a new VM
    destroy        Destroy the VM

    init           Full initialization (provision + start + wait)
    bake           Create baked image for instant resets
    reset          Reset VM to clean state (instant)
    rebuild        Full rebuild (destroy + provision + start)

    console-log    Tail serial console output
    status-full    Comprehensive status dashboard

Examples:
    $0 init                       # One-time setup (snap VM)
    VM_TYPE=deb $0 init           # One-time setup (deb VM)
    VM_TYPE=deb $0 bake           # After init, enable instant resets
    VM_TYPE=deb $0 reset          # Reset to clean state (instant)
    VM_TYPE=deb $0 status-full    # View full status
EOF
}

vm_create_overlay() {
    if [ ! -f "$BAKED_DISK" ]; then
        echo "ERROR: No baked image. Run: VM_TYPE=$VM_TYPE $0 bake"
        exit 1
    fi
    echo "Creating fresh overlay..."
    rm -f "$OVERLAY_DISK"
    qemu-img create -f qcow2 -b "$(basename "$BAKED_DISK")" -F qcow2 "$OVERLAY_DISK" >/dev/null 2>&1
}

vm_start() {
    if [ -f "$VM_PID_FILE" ] && kill -0 $(cat "$VM_PID_FILE") 2>/dev/null; then
        echo "VM is already running (PID: $(cat "$VM_PID_FILE"))"
        return 0
    fi

    if [ ! -f "$BASE_DISK" ]; then
        echo "ERROR: VM not provisioned. Run: VM_TYPE=$VM_TYPE $0 provision"
        exit 1
    fi

    # Use overlay if baked image exists, otherwise use base
    if [ -f "$BAKED_DISK" ]; then
        # Create overlay if it doesn't exist
        if [ ! -f "$OVERLAY_DISK" ]; then
            echo "Creating overlay from baked image..."
            vm_create_overlay
        fi
        DISK_IMAGE="$OVERLAY_DISK"
        echo "Using overlay (instant reset available)..."
    else
        DISK_IMAGE="$BASE_DISK"
        echo "Using base image (cloud-init will run)..."
    fi

    echo "Starting VM $VM_NAME..."
    mkdir -p "$VM_DIR/logs"
    qemu-system-x86_64 \
        -name "$VM_NAME" \
        -m 2048 \
        -smp 2 \
        -enable-kvm \
        -drive file="$DISK_IMAGE",format=qcow2 \
        -drive file="$VM_DIR/disks/${VM_NAME}-cidata.iso",format=raw \
        -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${TRIGGER_PORT}-:9000 \
        -device virtio-net-pci,netdev=net0 \
        -serial file:"$VM_DIR/logs/${VM_NAME}-console.log" \
        -display none \
        -daemonize \
        -pidfile "$VM_PID_FILE"

    echo "VM started (PID: $(cat "$VM_PID_FILE"))"
    echo "Waiting for health check..."

    local health_timeout=300
    local elapsed=0
    while [ $elapsed -lt $health_timeout ]; do
        if curl -s --connect-timeout 1 http://localhost:${TRIGGER_PORT}/health 2>/dev/null | grep -q OK; then
            echo "VM is healthy! (${elapsed}s)"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    if [ $elapsed -ge $health_timeout ]; then
        echo "WARNING: VM started but health check not responding after ${health_timeout}s"
        return 0
    fi

    # On a fresh base image, cloud-init may still be provisioning after the
    # trigger server comes up.  Wait for it to finish so the VM is fully
    # ready (important before baking).
    if [ "$DISK_IMAGE" = "$BASE_DISK" ]; then
        echo "Waiting for cloud-init to finish (base image, first boot)..."
        local SSH_OPTS="-i $VM_DIR/ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"
        if ssh $SSH_OPTS -p ${SSH_PORT} ${SSH_USER}@localhost "cloud-init status --wait" 2>/dev/null; then
            echo "cloud-init complete"
        else
            echo "WARNING: could not verify cloud-init status"
        fi
    fi
}

vm_stop() {
    if [ ! -f "$VM_PID_FILE" ]; then
        echo "VM is not running (no PID file)"
        return 0
    fi

    local pid=$(cat "$VM_PID_FILE")
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "VM is not running (stale PID file)"
        rm -f "$VM_PID_FILE"
        return 0
    fi

    echo "Stopping VM (PID: $pid)..."
    kill "$pid"
    sleep 2

    if kill -0 "$pid" 2>/dev/null; then
        echo "Forcing VM shutdown..."
        kill -9 "$pid" 2>/dev/null || true
    fi

    rm -f "$VM_PID_FILE"
    echo "VM stopped"
}

vm_status() {
    if [ -f "$VM_PID_FILE" ]; then
        local pid=$(cat "$VM_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "VM is running (PID: $pid)"
            return 0
        else
            echo "VM is not running (stale PID file)"
            return 1
        fi
    else
        echo "VM is not running"
        return 1
    fi
}

vm_health() {
    if curl -s --connect-timeout 2 http://localhost:${TRIGGER_PORT}/health 2>/dev/null | grep -q OK; then
        echo "VM health check: OK"
        return 0
    else
        echo "VM health check: FAILED"
        return 1
    fi
}

vm_ssh() {
    if [ ! -f "$VM_DIR/ssh/id_ed25519" ]; then
        echo "ERROR: SSH key not found. VM may not be provisioned."
        exit 1
    fi

    echo "Connecting to VM via SSH (${SSH_USER}@localhost:${SSH_PORT})..."
    ssh -p ${SSH_PORT} -i "$VM_DIR/ssh/id_ed25519" ${SSH_USER}@localhost "$@"
}

vm_logs() {
    vm_ssh "sudo journalctl -u ${SERVICE_NAME}.service -f"
}

vm_console() {
    echo "Attaching to VM console (use Ctrl-A X to exit)..."
    if [ -f "$VM_PID_FILE" ]; then
        local pid=$(cat "$VM_PID_FILE")
        socat -,raw,echo=0,escape=0x01 "unix-connect:/tmp/qemu-${pid}.monitor"
    else
        echo "ERROR: VM is not running"
        exit 1
    fi
}

vm_provision() {
    echo "Provisioning VM ($VM_TYPE)..."
    cd "$ANSIBLE_DIR"
    ansible-playbook "$PROVISION_PLAYBOOK"
    cd "$SCRIPT_DIR"
    echo "VM provisioned successfully"
}

vm_destroy() {
    echo "WARNING: This will delete the VM disk and all data."
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        vm_stop
        cd "$ANSIBLE_DIR"
        ansible-playbook "$DESTROY_PLAYBOOK"
        cd "$SCRIPT_DIR"
        echo "VM destroyed"
    else
        echo "Cancelled"
    fi
}

vm_bake() {
    echo "Baking VM image ($VM_TYPE)..."
    if [ ! -f "$BASE_DISK" ]; then
        echo "ERROR: VM not provisioned. Run: VM_TYPE=$VM_TYPE $0 provision"
        exit 1
    fi
    cd "$ANSIBLE_DIR"
    ansible-playbook "$BAKE_PLAYBOOK"
    cd "$SCRIPT_DIR"
    echo "Baked image created! You can now use 'VM_TYPE=$VM_TYPE $0 reset' for instant clean state resets."
}

vm_reset() {
    echo "Resetting VM to clean state ($VM_TYPE)..."
    vm_stop 2>/dev/null || true
    if [ ! -f "$BAKED_DISK" ]; then
        echo "ERROR: No baked image. Run: VM_TYPE=$VM_TYPE $0 bake first"
        exit 1
    fi
    vm_create_overlay
    echo "Reset complete. Run: VM_TYPE=$VM_TYPE $0 start"
}

vm_init() {
    echo "Full VM initialization (provision + start + wait)..."
    vm_provision
    vm_start
    echo ""
    echo "VM initialized and running!"
    echo "Run 'VM_TYPE=$VM_TYPE $0 bake' after verifying VM works to enable instant reset."
}

vm_rebuild() {
    echo "Full VM rebuild (destroy + provision + start)..."
    vm_destroy
    vm_provision
    vm_start
}

vm_console_log() {
    local log="$VM_DIR/logs/${VM_NAME}-console.log"
    if [ -f "$log" ]; then
        tail -f "$log"
    else
        echo "No console log found. Is VM running?"
        exit 1
    fi
}

vm_status_full() {
    echo "=== VM Status ($VM_TYPE) ==="
    vm_status || true
    echo ""
    echo "=== Health Check ==="
    vm_health || true
    echo ""
    echo "=== Last Boot Log ==="
    local log="$VM_DIR/logs/${VM_NAME}-console.log"
    if [ -f "$log" ]; then
        tail -5 "$log"
    else
        echo "No console log available"
    fi
    echo ""
    echo "=== Baked Image ==="
    if [ -f "$BAKED_DISK" ]; then
        if [ -f "$VM_DIR/disks/${VM_NAME}-baked.timestamp" ]; then
            echo "Available (created: $(cat "$VM_DIR/disks/${VM_NAME}-baked.timestamp"))"
        else
            echo "Available"
        fi
        if [ -f "$OVERLAY_DISK" ]; then
            echo "Overlay: Active"
        else
            echo "Overlay: Not created (will be created on next start)"
        fi
    else
        echo "Not created (run: VM_TYPE=$VM_TYPE $0 bake)"
    fi
}

# Main command dispatcher
case "${1:-}" in
    start)
        vm_start
        ;;
    stop)
        vm_stop
        ;;
    restart)
        vm_stop
        vm_start
        ;;
    status)
        vm_status
        ;;
    health)
        vm_health
        ;;
    ssh)
        shift
        vm_ssh "$@"
        ;;
    logs)
        vm_logs
        ;;
    console)
        vm_console
        ;;
    provision)
        vm_provision
        ;;
    destroy)
        vm_destroy
        ;;
    bake)
        vm_bake
        ;;
    reset)
        vm_reset
        ;;
    init)
        vm_init
        ;;
    rebuild)
        vm_rebuild
        ;;
    console-log)
        vm_console_log
        ;;
    status-full)
        vm_status_full
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
