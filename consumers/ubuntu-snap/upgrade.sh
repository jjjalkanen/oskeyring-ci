#!/bin/bash
set -e
echo "[consumer-ubuntu] Starting upgrade..."
REGISTRY="${SNAP_REGISTRY_URL:-http://snap-registry:8081}"
curl -s -o /tmp/access-keys.snap "${REGISTRY}/snaps/access-keys_0.1.0_amd64.snap"
snap install --dangerous --devmode /tmp/access-keys.snap
curl -s -o /tmp/firefox.snap "${REGISTRY}/snaps/firefox_latest_amd64.snap"
snap install --dangerous --devmode /tmp/firefox.snap

# Generate credential (64 random bytes, base64-encoded)
KEY_B64=$(head -c 64 /dev/urandom | base64 -w 0)
mkdir -p /etc/firefox
echo -n "$KEY_B64" | systemd-creds encrypt --name=sync-key \
    --with-key=host - /etc/firefox/sync.cred
# Stash plaintext key for direct test use (no systemd credential decryption needed)
mkdir -p /run/firefox-test-creds
echo -n "$KEY_B64" > /run/firefox-test-creds/sync-key

echo "[consumer-ubuntu] Upgrade complete"
