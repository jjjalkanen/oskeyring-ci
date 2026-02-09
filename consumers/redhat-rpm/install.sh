#!/bin/bash
set -e

echo "[consumer-redhat] Installing access-keys from rpm..."

# Wait for registry to be available
timeout 60 bash -c 'until curl -s http://rpm-registry:8083/ > /dev/null; do sleep 1; done'

# Update repository metadata
dnf makecache

# Install the package
dnf install -y access-keys

# Generate host key for systemd-creds (container has no TPM)
systemd-creds setup 2>/dev/null || true

# Encrypt a test secret
printf '%s' "0123456789abcdef" > /tmp/raw-sync.key
mkdir -p /etc/access-keys
systemd-creds encrypt --name=sync-key --with-key=host \
    /tmp/raw-sync.key /etc/access-keys/sync.cred
rm -f /tmp/raw-sync.key

echo "[consumer-redhat] Installation complete"
