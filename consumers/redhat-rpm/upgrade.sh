#!/bin/bash
set -e
echo "[consumer-redhat] Starting upgrade..."

dnf makecache -q
dnf upgrade -y access-keys || dnf install -y access-keys
dnf upgrade -y firefox || dnf install -y firefox

# access-keys demo credential (existing pattern)
printf '%s' "0123456789abcdef" > /tmp/raw-sync.key
mkdir -p /etc/access-keys
systemd-creds encrypt --name=sync-key --with-key=host \
    /tmp/raw-sync.key /etc/access-keys/sync.cred
rm -f /tmp/raw-sync.key

echo "[consumer-redhat] Upgrade complete"
