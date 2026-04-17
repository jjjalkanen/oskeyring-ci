#!/bin/bash
set -e

VM_NAME="snap-consumer-vm"
VM_PID_FILE="/tmp/${VM_NAME}.pid"
DEB_VM_NAME="deb-consumer-vm"
DEB_VM_PID_FILE="/tmp/${DEB_VM_NAME}.pid"

VALID_CONSUMERS=(consumer-arch consumer-debian consumer-redhat consumer-ubuntu)
SELECTED_CONSUMERS=()

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --build-only          Run only the Firefox build (./mach build), then exit."
    echo "                        Skips canary app, packaging, VM, and containers."
    echo "  --no-build            Skip ./mach build; use existing build artifacts for packaging."
    echo "                        Canary app is still built."
    echo "  --force-build         Proceed even if active mozconfig differs from both"
    echo "                        canonical configs, or if stored objdir configs mismatch."
    echo "  --consumer <name>     Only run the named consumer (repeatable)."
    echo "                        Valid names: ${VALID_CONSUMERS[*]}"
    echo "                        If omitted, all consumers are run."
    echo "  -h, --help            Show this help message."
}

consumer_enabled() {
    local name="$1"
    for c in "${SELECTED_CONSUMERS[@]}"; do
        [[ "$c" == "$name" ]] && return 0
    done
    return 1
}

# Compare mozconfigs ignoring blank lines, trailing whitespace, and line order
diff_mozconfigs() {
    local flag="$1" file_a="$2" file_b="$3"
    clean() { grep -v '^[[:space:]]*$' "$1" | sed 's/[[:space:]]*$//' | sort; }
    diff "$flag" <(clean "$file_a") <(clean "$file_b")
}

# Parse flags
BUILD_ONLY=false
NO_BUILD=false
FORCE_BUILD=false
while [ $# -gt 0 ]; do
    case "$1" in
        --build-only)  BUILD_ONLY=true ;;
        --no-build)    NO_BUILD=true ;;
        --force-build) FORCE_BUILD=true ;;
        --consumer)
            shift
            if [ $# -eq 0 ]; then
                echo "ERROR: --consumer requires a name"; echo ""; usage; exit 1
            fi
            valid=false
            for v in "${VALID_CONSUMERS[@]}"; do
                [[ "$v" == "$1" ]] && valid=true
            done
            if [ "$valid" = false ]; then
                echo "ERROR: Invalid consumer '$1'"
                echo "Valid consumers: ${VALID_CONSUMERS[*]}"
                exit 1
            fi
            SELECTED_CONSUMERS+=("$1")
            ;;
        -h|--help)     usage; exit 0 ;;
        *)             echo "Unknown option: $1"; echo ""; usage; exit 1 ;;
    esac
    shift
done

# Default to all consumers if none specified
if [ ${#SELECTED_CONSUMERS[@]} -eq 0 ]; then
    SELECTED_CONSUMERS=("${VALID_CONSUMERS[@]}")
fi

echo "=========================================="
echo "Podman Container Orchestration"
echo "=========================================="
echo ""

# Set kernel.core_pattern so core dumps land in a known location.
# This is a host-level setting (containers share the host kernel).
CORE_DIR=/tmp/cores
mkdir -p "$CORE_DIR"
if sudo sysctl -w kernel.core_pattern="$CORE_DIR/core.%e.%p.%t" 2>/dev/null; then
    echo "Core dump pattern set to $CORE_DIR/core.%e.%p.%t"
else
    echo "WARNING: Could not set kernel.core_pattern (no sudo?). Core dumps may not be captured."
fi

# Check prerequisites
check_prerequisites() {
    local failed=0

    echo "Checking prerequisites..."

    # Check for /dev/fuse (required for flatpak)
    if consumer_enabled consumer-arch && [ ! -e /dev/fuse ]; then
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

    # Check for qemu-system-x86_64 (required for snap and deb VMs)
    if (consumer_enabled consumer-ubuntu || consumer_enabled consumer-debian) && ! command -v qemu-system-x86_64 &>/dev/null; then
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
    if consumer_enabled consumer-ubuntu && [ ! -f "$SCRIPT_DIR/../vm/disks/${VM_NAME}.qcow2" ]; then
        echo "ERROR: Snap VM not provisioned. Run:"
        echo "  cd ansible && ansible-playbook playbooks/vm-provision.yml"
        exit 1
    fi
    if consumer_enabled consumer-debian && [ ! -f "$SCRIPT_DIR/../vm/disks/${DEB_VM_NAME}.qcow2" ]; then
        echo "ERROR: Deb VM not provisioned. Run:"
        echo "  cd ansible && ansible-playbook playbooks/deb-vm-provision.yml"
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
        -serial file:"$VM_DIR/logs/${VM_NAME}-console.log" \
        -display none \
        -daemonize \
        -pidfile "$VM_PID_FILE"

    echo "Waiting for VM to be ready..."
    VM_TRIGGER_PORT=9002 VM_LOG_FILE="$VM_DIR/logs/${VM_NAME}-console.log" ./scripts/vm-health-check.sh
}

# Stop VM function
stop_vm() {
    echo "Stopping snap-consumer-vm..."
    if [ -f "$VM_PID_FILE" ]; then
        kill $(cat "$VM_PID_FILE") 2>/dev/null || true
        rm -f "$VM_PID_FILE"
    fi
}

# Deb VM functions
reset_deb_vm_state() {
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    VM_DIR="$SCRIPT_DIR/../vm"
    BAKED_DISK="$VM_DIR/disks/${DEB_VM_NAME}-baked.qcow2"
    OVERLAY_DISK="$VM_DIR/disks/${DEB_VM_NAME}-overlay.qcow2"

    if [ -f "$BAKED_DISK" ]; then
        echo "Resetting deb VM to clean state..."
        rm -f "$OVERLAY_DISK"
        qemu-img create -f qcow2 -b "$(basename "$BAKED_DISK")" -F qcow2 "$OVERLAY_DISK" >/dev/null 2>&1
        echo "Deb VM state reset (using overlay)"
    fi
}

start_deb_vm() {
    echo "Starting deb-consumer-vm..."

    if [ -f "$DEB_VM_PID_FILE" ] && kill -0 $(cat "$DEB_VM_PID_FILE") 2>/dev/null; then
        echo "Deb VM already running"
        return 0
    fi

    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    VM_DIR="$SCRIPT_DIR/../vm"
    BAKED_DISK="$VM_DIR/disks/${DEB_VM_NAME}-baked.qcow2"
    OVERLAY_DISK="$VM_DIR/disks/${DEB_VM_NAME}-overlay.qcow2"
    BASE_DISK="$VM_DIR/disks/${DEB_VM_NAME}.qcow2"

    if [ -f "$BAKED_DISK" ]; then
        DISK_IMAGE="$OVERLAY_DISK"
        echo "Using baked image with overlay (fast boot)..."
    else
        DISK_IMAGE="$BASE_DISK"
        echo "Using base image (cloud-init will run)..."
    fi

    mkdir -p "$VM_DIR/logs"
    qemu-system-x86_64 \
        -name "$DEB_VM_NAME" \
        -m 2048 \
        -smp 2 \
        -enable-kvm \
        -drive file="$DISK_IMAGE",format=qcow2 \
        -drive file="$VM_DIR/disks/${DEB_VM_NAME}-cidata.iso",format=raw \
        -netdev user,id=net0,hostfwd=tcp::2223-:22,hostfwd=tcp::9003-:9000 \
        -device virtio-net-pci,netdev=net0 \
        -serial file:"$VM_DIR/logs/${DEB_VM_NAME}-console.log" \
        -display none \
        -daemonize \
        -pidfile "$DEB_VM_PID_FILE"

    echo "Waiting for deb VM to be ready..."
    VM_TRIGGER_PORT=9003 VM_LOG_FILE="$VM_DIR/logs/${DEB_VM_NAME}-console.log" ./scripts/vm-health-check.sh
}

stop_deb_vm() {
    echo "Stopping deb-consumer-vm..."
    if [ -f "$DEB_VM_PID_FILE" ]; then
        kill $(cat "$DEB_VM_PID_FILE") 2>/dev/null || true
        rm -f "$DEB_VM_PID_FILE"
    fi
}

# Cleanup handler
TIMEOUT_MINUTES=120
CLEANUP_DONE=false

cleanup() {
    if [ "$CLEANUP_DONE" = true ]; then return; fi
    CLEANUP_DONE=true
    if [ "$BUILD_ONLY" = true ]; then return; fi
    echo "Cleaning up..."
    podman-compose --in-pod=0 down --timeout 10 2>/dev/null || {
        podman stop -a -t 5 2>/dev/null || true
        podman rm -a -f 2>/dev/null || true
    }
    if consumer_enabled consumer-ubuntu; then
        stop_vm
    fi
    if consumer_enabled consumer-debian; then
        stop_deb_vm
    fi
}

trap cleanup EXIT INT TERM

# Run prerequisite checks
if [ "$BUILD_ONLY" = true ]; then
    echo "Build-only mode: skipping prerequisite checks and VM setup"
    echo ""
else
    check_prerequisites
    if consumer_enabled consumer-ubuntu || consumer_enabled consumer-debian; then
        check_vm_prerequisites
    fi

    # Step 1: Create network
    echo "Step 1: Creating network..."
    ./scripts/create-network.sh
    echo ""

    # Step 2: Start VMs
    if consumer_enabled consumer-ubuntu; then
        echo "Step 2: Starting snap consumer VM..."
        reset_vm_state
        start_vm
        echo ""
    fi
    if consumer_enabled consumer-debian; then
        echo "Step 2b: Starting deb consumer VM..."
        reset_deb_vm_state
        start_deb_vm
        echo ""
    fi
    if ! consumer_enabled consumer-ubuntu && ! consumer_enabled consumer-debian; then
        echo "Step 2: Skipping VMs (neither consumer-ubuntu nor consumer-debian selected)"
        echo ""
    fi
fi

if [ "$BUILD_ONLY" != true ] && consumer_enabled consumer-ubuntu; then
# Step 2.5: Update scripts in snap VM
echo "Step 2.5: Updating scripts in snap VM..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_OPTS="-i $SCRIPT_DIR/../vm/ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=2"

# Wait for SSH to be ready (max 60 seconds)
echo "Waiting for SSH to be ready on port 2222..."
for i in {1..60}; do
    if ssh $SSH_OPTS -p 2222 testrunner@localhost "exit" 2>/dev/null; then
        echo "SSH is ready"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "WARNING: SSH not ready after 60 seconds, skipping script update"
        echo ""
    else
        sleep 1
    fi
done

# Copy and update scripts if SSH is ready
if ssh $SSH_OPTS -p 2222 testrunner@localhost "exit" 2>/dev/null; then
    scp_snap() {
        scp -i "$SCRIPT_DIR/../vm/ssh/id_ed25519" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -P 2222 "$1" testrunner@localhost:/tmp/"$(basename "$1")" \
            2>&1 | grep -v "Warning: Permanently added" || true
    }
    ssh_snap() {
        ssh $SSH_OPTS -p 2222 testrunner@localhost "$@" \
            2>&1 | grep -v "Warning: Permanently added" || true
    }

    # Push shared trigger-server scripts
    for script in server.py test-runner.py wpt-runner.py idb-verify.py; do
        scp_snap "$SCRIPT_DIR/../consumers/trigger-server/$script"
        ssh_snap "sudo mv /tmp/$script /opt/snap-consumer/$script && sudo chmod +x /opt/snap-consumer/$script"
    done

    # Push upgrade.sh
    scp_snap "$SCRIPT_DIR/../consumers/ubuntu-snap/upgrade.sh"
    ssh_snap "sudo mv /tmp/upgrade.sh /opt/snap-consumer/upgrade.sh && sudo chmod +x /opt/snap-consumer/upgrade.sh"

    # Restart service to pick up new server.py
    ssh_snap "sudo systemctl daemon-reload && sudo systemctl restart snap-consumer"

    # Clear snap data from previous test runs
    echo "Clearing snap data from previous runs..."
    ssh_snap "sudo rm -rf /var/snap/access-keys/current/* 2>/dev/null || true"

    echo "Snap VM scripts updated successfully"
fi
echo ""
fi  # end BUILD_ONLY != true && consumer-ubuntu enabled

if [ "$BUILD_ONLY" != true ] && consumer_enabled consumer-debian; then
# Step 2.5b: Update scripts in deb VM
echo "Step 2.5b: Updating scripts in deb VM..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_OPTS="-i $SCRIPT_DIR/../vm/ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=2"

# Wait for SSH to be ready on port 2223 (max 60 seconds)
echo "Waiting for SSH to be ready on port 2223..."
for i in {1..60}; do
    if ssh $SSH_OPTS -p 2223 consumer@localhost "exit" 2>/dev/null; then
        echo "SSH is ready"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "WARNING: SSH not ready after 60 seconds, skipping script update"
        echo ""
    else
        sleep 1
    fi
done

# Copy and update scripts if SSH is ready
if ssh $SSH_OPTS -p 2223 consumer@localhost "exit" 2>/dev/null; then
    scp_deb() {
        scp -i "$SCRIPT_DIR/../vm/ssh/id_ed25519" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -P 2223 "$1" consumer@localhost:/tmp/"$(basename "$1")" \
            2>&1 | grep -v "Warning: Permanently added" || true
    }
    ssh_deb() {
        ssh $SSH_OPTS -p 2223 consumer@localhost "$@" \
            2>&1 | grep -v "Warning: Permanently added" || true
    }

    # Push shared trigger-server scripts
    for script in server.py test-runner.py wpt-runner.py idb-verify.py; do
        scp_deb "$SCRIPT_DIR/../consumers/trigger-server/$script"
        ssh_deb "sudo mv /tmp/$script /home/consumer/$script && sudo chown consumer:consumer /home/consumer/$script && sudo chmod +x /home/consumer/$script"
    done

    # Push upgrade.sh
    scp_deb "$SCRIPT_DIR/../consumers/debian-apt/upgrade.sh"
    ssh_deb "sudo mv /tmp/upgrade.sh /home/consumer/upgrade.sh && sudo chown consumer:consumer /home/consumer/upgrade.sh && sudo chmod +x /home/consumer/upgrade.sh"

    # Restart trigger-server to pick up new server.py
    ssh_deb "sudo systemctl daemon-reload && sudo systemctl restart trigger-server"

    echo "Deb VM scripts updated successfully"
fi
echo ""
fi  # end BUILD_ONLY != true && consumer-debian enabled

# Step 3: Build on host
echo "Step 3: Building on host..."
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
mkdir -p "$PROJECT_DIR/dist"

CANONICAL_MOZCONFIG="$PROJECT_DIR/builder/scripts/firefox-mozconfig"
RHEL9_MOZCONFIG="$PROJECT_DIR/builder/scripts/firefox-mozconfig-rhel9"

# Ensure bootstrapped tools (llvm-objdump, etc.) are on PATH
if [ -d "$HOME/.mozbuild/clang/bin" ]; then
    export PATH="$HOME/.mozbuild/clang/bin:$PATH"
fi

# Step 3a: Mozconfig validation
echo "Step 3a: Validating mozconfig files..."
cd "$PROJECT_DIR/firefox"
VALIDATION_FAILED=false

rotate_mozconfig() {
    local dir="$PROJECT_DIR/firefox"
    local latest
    latest=$(ls -t "$dir"/mozconfig.[1-8] 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
        local n="${latest##*.}"
        local next=$(( (n % 8) + 1 ))
    else
        local next=1
    fi
    mv "$dir/mozconfig" "$dir/mozconfig.$next"
    echo "  Backed up firefox/mozconfig → firefox/mozconfig.$next"
}

# Check 1: firefox/mozconfig must match builder/scripts/firefox-mozconfig
TREE_MOZCONFIG="$PROJECT_DIR/firefox/mozconfig"
if [ -f "$TREE_MOZCONFIG" ]; then
    if ! diff_mozconfigs -q "$TREE_MOZCONFIG" "$CANONICAL_MOZCONFIG" >/dev/null 2>&1; then
        echo "ERROR: firefox/mozconfig does not match builder/scripts/firefox-mozconfig:"
        diff_mozconfigs -u "$TREE_MOZCONFIG" "$CANONICAL_MOZCONFIG" || true
        if [ "$FORCE_BUILD" = true ]; then
            rotate_mozconfig
            echo "  --force-build: replacing firefox/mozconfig with canonical config"
            cp "$CANONICAL_MOZCONFIG" "$TREE_MOZCONFIG"
        else
            echo "  Pass --force-build to overwrite firefox/mozconfig with the canonical config."
            VALIDATION_FAILED=true
        fi
    else
        echo "  firefox/mozconfig matches canonical config (obj-fx-dbg) ✓"
    fi
else
    echo "  firefox/mozconfig not found — creating from canonical config"
    cp "$CANONICAL_MOZCONFIG" "$TREE_MOZCONFIG"
fi

# Check 2: obj-fx-rhel9/.mozconfig vs builder/scripts/firefox-mozconfig-rhel9
RHEL9_OBJDIR="$PROJECT_DIR/obj-fx-rhel9"
if [ -f "$RHEL9_OBJDIR/.mozconfig" ]; then
    if ! diff_mozconfigs -q "$RHEL9_OBJDIR/.mozconfig" "$RHEL9_MOZCONFIG" >/dev/null 2>&1; then
        echo "ERROR: obj-fx-rhel9/.mozconfig differs from builder/scripts/firefox-mozconfig-rhel9:"
        diff_mozconfigs -u "$RHEL9_OBJDIR/.mozconfig" "$RHEL9_MOZCONFIG" || true
        if [ "$FORCE_BUILD" != true ]; then
            echo "  A rebuild would clobber. Pass --force-build to override."
            VALIDATION_FAILED=true
        else
            echo "  --force-build: proceeding despite stored config mismatch"
        fi
    else
        echo "  obj-fx-rhel9/.mozconfig matches rhel9 config ✓"
    fi
fi

# Check 3: obj-fx-dbg/.mozconfig vs builder/scripts/firefox-mozconfig (only needed for native consumers)
DBG_OBJDIR="$PROJECT_DIR/obj-fx-dbg"
if (consumer_enabled consumer-arch || consumer_enabled consumer-debian || consumer_enabled consumer-ubuntu) && [ -f "$DBG_OBJDIR/.mozconfig" ]; then
    if ! diff_mozconfigs -q "$DBG_OBJDIR/.mozconfig" "$CANONICAL_MOZCONFIG" >/dev/null 2>&1; then
        echo "ERROR: obj-fx-dbg/.mozconfig differs from builder/scripts/firefox-mozconfig:"
        diff_mozconfigs -u "$DBG_OBJDIR/.mozconfig" "$CANONICAL_MOZCONFIG" || true
        if [ "$FORCE_BUILD" != true ]; then
            echo "  A rebuild would clobber. Pass --force-build to override."
            VALIDATION_FAILED=true
        else
            echo "  --force-build: proceeding despite stored config mismatch"
        fi
    else
        echo "  obj-fx-dbg/.mozconfig matches canonical config ✓"
    fi
fi

if [ "$VALIDATION_FAILED" = true ]; then
    echo ""
    echo "Mozconfig validation failed. Fix the issues above or pass --force-build."
    exit 1
fi
echo ""

# Determine which Firefox flavors are needed based on selected consumers
NEED_NATIVE_BUILD=false
NEED_RHEL9_BUILD=false
if consumer_enabled consumer-arch || consumer_enabled consumer-debian || consumer_enabled consumer-ubuntu; then
    NEED_NATIVE_BUILD=true
fi
if consumer_enabled consumer-redhat; then
    NEED_RHEL9_BUILD=true
fi

# Step 3b: Firefox builds (unless --no-build)
if [ "$NO_BUILD" != true ]; then
    # Step 3b-1: Host-native Firefox build (for DEB, Flatpak, Snap)
    if [ "$NEED_NATIVE_BUILD" = true ]; then
        echo "Step 3b-1: Building Firefox (host-native)..."
        export MOZCONFIG="$CANONICAL_MOZCONFIG"
        env -u CLAUDECODE ./mach build
        echo ""
    else
        echo "Step 3b-1: Skipping host-native build (no consumers require it)"
    fi

    # Step 3b-2: RHEL9-targeted Firefox build (for RPM)
    if [ "$NEED_RHEL9_BUILD" = true ]; then
        echo "Step 3b-2: Building Firefox (RHEL9-targeted)..."
        if [ ! -f "$PROJECT_DIR/dist/onnxruntime-rhel9/libonnxruntime.so" ]; then
            echo "ERROR: RHEL9 onnxruntime not found at dist/onnxruntime-rhel9/libonnxruntime.so"
            echo "Run ./scripts/build-onnxruntime-rhel9.sh first."
            exit 1
        fi
        export MOZCONFIG="$RHEL9_MOZCONFIG"
        env -u CLAUDECODE ./mach build
    else
        echo "Step 3b-2: Skipping RHEL9 build (no consumers require it)"
    fi

    if [ "$BUILD_ONLY" = true ]; then
        echo "Firefox builds complete."
        exit 0
    fi
else
    echo "Step 3b: Skipping Firefox build (--no-build)"
fi
echo ""

# Step 3c: Build canary app (single unified binary)
echo "Step 3c: Building canary app..."
cd "$PROJECT_DIR/app"

cargo build --release
cp target/release/access-keys "$PROJECT_DIR/dist/access-keys"

echo "Building firefox-credential-server..."
cd "$PROJECT_DIR/credential-server"
cargo build --release
cp target/release/firefox-credential-server "$PROJECT_DIR/dist/firefox-credential-server"

echo ""

# Step 3d: Package Firefox (only flavors needed by selected consumers)
echo "Step 3d: Packaging Firefox..."
cd "$PROJECT_DIR/firefox"

if [ "$NEED_NATIVE_BUILD" = true ]; then
    # Package host-native build (for DEB, Flatpak, Snap)
    echo "  Packaging host-native build..."
    export MOZCONFIG="$CANONICAL_MOZCONFIG"
    env -u CLAUDECODE ./mach package
    cp "$(ls -t "$PROJECT_DIR/obj-fx-dbg/dist"/firefox-*.tar.xz | head -1)" "$PROJECT_DIR/dist/firefox.tar.xz"
    cp "$PROJECT_DIR/obj-fx-dbg/x86_64-unknown-linux-gnu/debug/geckodriver" "$PROJECT_DIR/dist/geckodriver"
else
    echo "  Skipping host-native packaging (not needed)"
fi

if [ "$NEED_RHEL9_BUILD" = true ]; then
    # Package RHEL9 build (for RPM)
    echo "  Packaging RHEL9 build..."
    export MOZCONFIG="$RHEL9_MOZCONFIG"
    env -u CLAUDECODE ./mach package
    cp "$(ls -t "$PROJECT_DIR/obj-fx-rhel9/dist"/firefox-*.tar.xz | head -1)" "$PROJECT_DIR/dist/firefox-rhel9.tar.xz"
    cp "$PROJECT_DIR/obj-fx-rhel9/x86_64-unknown-linux-gnu/debug/geckodriver" "$PROJECT_DIR/dist/geckodriver-rhel9"
else
    echo "  Skipping RHEL9 packaging (not needed)"
fi

cd "$PROJECT_DIR"

echo ""
echo "Step 3e: Validating artifacts..."
MISSING=0
REQUIRED_ARTIFACTS=(access-keys firefox-credential-server)
[ "$NEED_NATIVE_BUILD" = true ] && REQUIRED_ARTIFACTS+=(firefox.tar.xz geckodriver)
[ "$NEED_RHEL9_BUILD" = true ]  && REQUIRED_ARTIFACTS+=(firefox-rhel9.tar.xz geckodriver-rhel9)
for artifact in "${REQUIRED_ARTIFACTS[@]}"; do
    if [ ! -f "$PROJECT_DIR/dist/$artifact" ]; then
        echo "  MISSING: dist/$artifact"
        MISSING=1
    else
        echo "  OK: dist/$artifact"
    fi
done
if [ $MISSING -ne 0 ]; then
    echo "ERROR: Host build produced incomplete artifacts"
    exit 1
fi
echo "Host build complete."
echo ""

# Step 4: Build images
echo "Step 4: Building container images..."
echo ""

# Build filtered service list
COMPOSE_SERVICES=(builder)
consumer_enabled consumer-arch   && COMPOSE_SERVICES+=(flatpak-registry consumer-arch) || true
consumer_enabled consumer-debian && COMPOSE_SERVICES+=(deb-registry) || true
consumer_enabled consumer-redhat && COMPOSE_SERVICES+=(rpm-registry consumer-redhat) || true
consumer_enabled consumer-ubuntu && COMPOSE_SERVICES+=(snap-registry) || true

echo "Services: ${COMPOSE_SERVICES[*]}"
export ENABLED_CONSUMERS="$(IFS=,; echo "${SELECTED_CONSUMERS[*]}")"

podman-compose --in-pod=0 build "${COMPOSE_SERVICES[@]}"

# Step 5: Start services
echo ""
echo "Step 5: Starting services: ${COMPOSE_SERVICES[*]}"
echo "Note: Builder will run to completion, then containers will be stopped"
echo ""

podman-compose --in-pod=0 up -d --force-recreate "${COMPOSE_SERVICES[@]}"

# Verify all services actually started (fast-fail — don't wait 2h for a dead run)
echo "Verifying services started..."
sleep 3
FAILED_SERVICES=()
for svc in "${COMPOSE_SERVICES[@]}"; do
    if ! podman ps --format '{{.Names}}' | grep -q "^${svc}$"; then
        FAILED_SERVICES+=("$svc")
        echo "  ERROR: $svc did not start"
        echo "  --- $svc startup logs ---"
        podman logs "$svc" 2>&1 | tail -20 || echo "  (no logs available)"
        echo "  --- end $svc logs ---"
    else
        echo "  OK: $svc is running"
    fi
done
if [ ${#FAILED_SERVICES[@]} -ne 0 ]; then
    echo "ERROR: ${#FAILED_SERVICES[@]} service(s) failed to start: ${FAILED_SERVICES[*]}"
    exit 1
fi

# Wait for builder to complete
echo "Waiting for builder to complete (timeout: ${TIMEOUT_MINUTES} minutes)..."
START_TIME=$(date +%s)
while podman ps --format '{{.Names}}' | grep -q '^builder$'; do
    ELAPSED=$(($(date +%s) - START_TIME))
    if [ $ELAPSED -ge $((TIMEOUT_MINUTES * 60)) ]; then
        echo "ERROR: Timeout after ${TIMEOUT_MINUTES} minutes"
        echo "--- builder logs (last 50 lines) ---"
        podman logs builder 2>&1 | tail -50
        exit 1
    fi
    # Print a heartbeat every 30s so we know the run is alive
    if (( ELAPSED % 30 == 0 && ELAPSED > 0 )); then
        echo "  Still running... (${ELAPSED}s elapsed)"
        # Also check if any non-builder service died unexpectedly
        for svc in "${COMPOSE_SERVICES[@]}"; do
            [[ "$svc" == "builder" ]] && continue
            if ! podman ps --format '{{.Names}}' | grep -q "^${svc}$"; then
                echo "  WARNING: $svc stopped unexpectedly"
                podman logs "$svc" 2>&1 | tail -10
            fi
        done
    fi
    sleep 2
done

# Show builder logs for results
echo ""
echo "=========================================="
echo "Builder Results"
echo "=========================================="
podman logs builder 2>&1 | grep -A 100 "TEST RESULTS SUMMARY" || podman logs builder 2>&1 | tail -50

# Get builder exit code
BUILDER_EXIT=$(podman inspect builder --format '{{.State.ExitCode}}' 2>/dev/null || echo "1")

# Extract WPT reports from builder container
mkdir -p "$PROJECT_DIR/wpt-reports"
podman cp builder:/home/builder/wpt-reports/. "$PROJECT_DIR/wpt-reports/" 2>/dev/null || true

# Validate WPT reports against Firefox metadata
if ls "$PROJECT_DIR/wpt-reports/"*.json 1>/dev/null 2>&1; then
    echo ""
    echo "=========================================="
    echo "WPT Metadata Validation"
    echo "=========================================="
    FIREFOX_DIR="$PROJECT_DIR/firefox"
    for report in "$PROJECT_DIR/wpt-reports/"*.json; do
        consumer=$(basename "$report" .json)
        echo "Validating $consumer report..."
        (cd "$FIREFOX_DIR" && ./mach wpt-update "$report" 2>&1) || true

        # Check if metadata changed
        meta_diff=$(cd "$FIREFOX_DIR" && git diff --name-only testing/web-platform/meta/)
        if [ -z "$meta_diff" ]; then
            echo "  $consumer: metadata unchanged -- tests match expectations"
        else
            echo "  $consumer: metadata CHANGED -- unexpected test results:"
            (cd "$FIREFOX_DIR" && git diff testing/web-platform/meta/)
        fi

        # Always restore metadata state
        (cd "$FIREFOX_DIR" && git checkout testing/web-platform/meta/) 2>/dev/null || true
    done
fi

# Stop all services
echo ""
echo "Stopping services..."
podman-compose --in-pod=0 down "${COMPOSE_SERVICES[@]}"

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
