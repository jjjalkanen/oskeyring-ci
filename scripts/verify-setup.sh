#!/bin/bash

echo "=========================================="
echo "Verifying Podman Orchestration Setup"
echo "=========================================="
echo ""

ERRORS=0

# Check for required commands
echo "Checking required commands..."
for cmd in podman podman-compose; do
    if command -v $cmd &> /dev/null; then
        echo "✓ $cmd found"
    else
        echo "✗ $cmd not found"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# Check for required directories
echo "Checking directory structure..."
DIRS=(
    "app/src"
    "builder/scripts"
    "registries/flatpak"
    "registries/snap"
    "registries/deb"
    "registries/rpm"
    "consumers/trigger-server"
    "consumers/arch-flatpak"
    "consumers/ubuntu-snap"
    "consumers/debian-apt"
    "consumers/redhat-rpm"
    "scripts"
)

for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "✓ $dir exists"
    else
        echo "✗ $dir missing"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# Check for key files
echo "Checking key files..."
FILES=(
    "app/Cargo.toml"
    "app/src/main.rs"
    "docker-compose.yml"
    "builder/Dockerfile"
    "builder/scripts/entrypoint.sh"
    "consumers/trigger-server/server.py"
    "consumers/trigger-server/test-runner.py"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✓ $file exists"
    else
        echo "✗ $file missing"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# Check network
echo "Checking Podman network..."
if podman network exists podman-build-network; then
    echo "✓ podman-build-network exists"
else
    echo "⚠ podman-build-network not created yet (run ./scripts/create-network.sh)"
fi
echo ""

# Summary
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo "✓ Setup verification passed!"
    echo "=========================================="
    echo ""
    echo "Ready to run: ./scripts/run-orchestration.sh"
    exit 0
else
    echo "✗ Setup verification failed with $ERRORS error(s)"
    echo "=========================================="
    exit 1
fi
