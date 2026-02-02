#!/bin/bash
set -e

echo "=========================================="
echo "Cleaning up Podman environment"
echo "=========================================="

cd "$(dirname "$0")/.."

echo "Stopping all containers (1 second timeout)..."
podman stop -a -t 1 2>/dev/null || true

echo "Killing any remaining containers..."
podman kill -a 2>/dev/null || true

echo "Removing all containers..."
podman rm -a -f 2>/dev/null || true

echo "Removing all pods..."
podman pod rm -a -f 2>/dev/null || true

echo "Pruning system (removing unused images, volumes, networks)..."
podman system prune -a -f --volumes 2>/dev/null || true

echo "Removing podman-build-network..."
podman network rm podman-build-network 2>/dev/null || true

echo "Recreating podman-build-network..."
./scripts/create-network.sh

echo "=========================================="
echo "Cleanup complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Build only:  podman-compose build"
echo "  2. Build & run: podman-compose up --build"
