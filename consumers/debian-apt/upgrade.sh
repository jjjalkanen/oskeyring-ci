#!/bin/bash
set -e
echo "[consumer-debian] Starting upgrade..."

apt-get update -qq
apt-get install -y access-keys
apt-get install -y firefox

# access-keys demo credential (existing pattern)
printf '%s' "0123456789abcdef" > /tmp/raw-sync.key
mkdir -p /etc/access-keys
systemd-creds encrypt --name=sync-key --with-key=host \
    /tmp/raw-sync.key /etc/access-keys/sync.cred
rm -f /tmp/raw-sync.key

echo "[consumer-debian] Upgrade complete"
