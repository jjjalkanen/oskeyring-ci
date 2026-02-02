#!/bin/bash
set -e

echo "[consumer-debian] Installing access-keys from apt..."

# Wait for registry to be available
timeout 60 bash -c 'until curl -s http://deb-registry:8082/ > /dev/null; do sleep 1; done'

# Update package lists
apt-get update

# Install the package
apt-get install -y access-keys

echo "[consumer-debian] Installation complete"
