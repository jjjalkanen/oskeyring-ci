#!/bin/bash
# Verification script for VM improvements
# This checks that all the new features are properly configured

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VM_DIR="$SCRIPT_DIR/../vm"

echo "=========================================="
echo "VM Improvements Verification"
echo "=========================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Test 1: Check vm-ctl.sh has new commands
echo "Test 1: Checking vm-ctl.sh commands..."
if grep -q "vm_bake()" "$SCRIPT_DIR/vm-ctl.sh"; then
    pass "vm_bake function exists"
else
    fail "vm_bake function missing"
fi

if grep -q "vm_reset()" "$SCRIPT_DIR/vm-ctl.sh"; then
    pass "vm_reset function exists"
else
    fail "vm_reset function missing"
fi

if grep -q "vm_init()" "$SCRIPT_DIR/vm-ctl.sh"; then
    pass "vm_init function exists"
else
    fail "vm_init function missing"
fi

if grep -q "vm_console_log()" "$SCRIPT_DIR/vm-ctl.sh"; then
    pass "vm_console_log function exists"
else
    fail "vm_console_log function missing"
fi

if grep -q "vm_status_full()" "$SCRIPT_DIR/vm-ctl.sh"; then
    pass "vm_status_full function exists"
else
    fail "vm_status_full function missing"
fi

# Test 2: Check overlay disk variables
echo ""
echo "Test 2: Checking overlay disk configuration..."
if grep -q "OVERLAY_DISK=" "$SCRIPT_DIR/vm-ctl.sh"; then
    pass "OVERLAY_DISK variable defined"
else
    fail "OVERLAY_DISK variable missing"
fi

if grep -q "BAKED_DISK=" "$SCRIPT_DIR/vm-ctl.sh"; then
    pass "BAKED_DISK variable defined"
else
    fail "BAKED_DISK variable missing"
fi

# Test 3: Check serial console logging
echo ""
echo "Test 3: Checking serial console logging..."
if grep -q -- "-serial file:" "$SCRIPT_DIR/vm-ctl.sh"; then
    pass "Serial console logging in vm-ctl.sh"
else
    fail "Serial console logging missing in vm-ctl.sh"
fi

if grep -q -- "-serial file:" "$SCRIPT_DIR/run-orchestration.sh"; then
    pass "Serial console logging in run-orchestration.sh"
else
    fail "Serial console logging missing in run-orchestration.sh"
fi

# Test 4: Check cloud-init has progress markers
echo ""
echo "Test 4: Checking cloud-init progress markers..."
if grep -q "\\[cloud-init\\]" "$SCRIPT_DIR/../ansible/roles/snap_consumer/templates/user-data.j2"; then
    pass "Cloud-init progress markers present"
else
    fail "Cloud-init progress markers missing"
fi

if grep -q "/dev/ttyS0" "$SCRIPT_DIR/../ansible/roles/snap_consumer/templates/user-data.j2"; then
    pass "Serial console output in cloud-init"
else
    fail "Serial console output missing in cloud-init"
fi

# Test 5: Check vm-health-check.sh shows progress
echo ""
echo "Test 5: Checking health check improvements..."
if grep -q "console.log" "$SCRIPT_DIR/vm-health-check.sh"; then
    pass "Health check reads console log"
else
    fail "Health check doesn't read console log"
fi

if grep -q "cloud-init" "$SCRIPT_DIR/vm-health-check.sh"; then
    pass "Health check displays cloud-init progress"
else
    fail "Health check doesn't display progress"
fi

# Test 6: Check run-orchestration.sh uses reset
echo ""
echo "Test 6: Checking orchestration integration..."
if grep -q "reset_vm_state()" "$SCRIPT_DIR/run-orchestration.sh"; then
    pass "reset_vm_state function defined"
else
    fail "reset_vm_state function missing"
fi

if grep -q "reset_vm_state$" "$SCRIPT_DIR/run-orchestration.sh"; then
    pass "reset_vm_state called before VM start"
else
    warn "reset_vm_state not called (might be optional)"
fi

# Test 7: Check ansible playbook exists
echo ""
echo "Test 7: Checking ansible playbooks..."
if [ -f "$SCRIPT_DIR/../ansible/playbooks/vm-bake.yml" ]; then
    pass "vm-bake.yml playbook exists"
else
    fail "vm-bake.yml playbook missing"
fi

# Test 8: Check logs directory
echo ""
echo "Test 8: Checking logs directory..."
if [ -d "$VM_DIR/logs" ]; then
    pass "vm/logs directory exists"
else
    warn "vm/logs directory missing (will be created on first run)"
fi

# Test 9: Check .gitignore
echo ""
echo "Test 9: Checking .gitignore..."
if grep -q "vm/logs/" "$SCRIPT_DIR/../.gitignore"; then
    pass "vm/logs/ in .gitignore"
else
    fail "vm/logs/ not in .gitignore"
fi

# Test 10: Check documentation
echo ""
echo "Test 10: Checking documentation..."
if [ -f "$VM_DIR/README.md" ]; then
    pass "vm/README.md exists"
else
    warn "vm/README.md missing"
fi

if [ -f "$SCRIPT_DIR/../VM_IMPROVEMENTS_SUMMARY.md" ]; then
    pass "VM_IMPROVEMENTS_SUMMARY.md exists"
else
    warn "VM_IMPROVEMENTS_SUMMARY.md missing"
fi

# Summary
echo ""
echo "=========================================="
echo "Verification Complete"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Run: ./scripts/vm-ctl.sh init    (one-time setup)"
echo "2. Run: ./scripts/vm-ctl.sh bake    (create snapshot)"
echo "3. Test: ./scripts/run-orchestration.sh"
echo ""
echo "For help: ./scripts/vm-ctl.sh"
