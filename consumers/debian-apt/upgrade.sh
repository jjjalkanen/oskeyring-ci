#!/bin/bash
set -e
echo "[consumer-debian] Starting upgrade..."

apt-get update -qq
apt-get install -y access-keys

# Fix mount propagation so systemd credential loading works in containers.
# Without this, sd-mkdcreds creates credentials in a child mount namespace
# that vanishes on exit.  See https://github.com/systemd/systemd/issues/38103
mount --make-rshared /

# Ensure systemd host key exists (idempotent - only creates if missing)
systemd-creds setup 2>/dev/null || true

# Set up systemd encrypted credential
printf '%s' "0123456789abcdef" > /tmp/raw-sync.key
mkdir -p /etc/access-keys
systemd-creds encrypt --name=sync-key --with-key=host \
    /tmp/raw-sync.key /etc/access-keys/sync.cred
rm -f /tmp/raw-sync.key

echo "[consumer-debian] Upgrade complete"
