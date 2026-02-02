#!/bin/bash
set -e

echo "[consumer-redhat] Installing access-keys from rpm..."

# Wait for registry to be available
timeout 60 bash -c 'until curl -s http://rpm-registry:8083/ > /dev/null; do sleep 1; done'

# Update repository metadata
dnf makecache

# Install the package
dnf install -y access-keys

echo "[consumer-redhat] Installation complete"
