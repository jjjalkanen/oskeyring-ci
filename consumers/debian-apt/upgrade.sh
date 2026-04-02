#!/bin/bash
set -e
echo "[consumer-debian] Starting upgrade..."

apt-get update -qq
apt-get install -y access-keys
apt-get install -y firefox

# access-keys demo credential (64 random bytes, base64-encoded for string transport)
KEY_B64=$(head -c 64 /dev/urandom | base64 -w 0)
mkdir -p /etc/firefox
echo -n "$KEY_B64" | systemd-creds encrypt --name=sync-key \
    --with-key=host - /etc/firefox/sync.cred
# Stash plaintext key for direct test use (no systemd credential decryption needed)
mkdir -p /run/firefox-test-creds
echo -n "$KEY_B64" > /run/firefox-test-creds/sync-key

# Enable and start firefox-credential-server (installed by deb postinst)
systemctl daemon-reload
systemctl enable --now firefox-credential-server.service 2>/dev/null || true

echo "[consumer-debian] Upgrade complete"
