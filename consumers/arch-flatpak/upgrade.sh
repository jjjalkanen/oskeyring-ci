#!/bin/bash
set -e
echo "[consumer-arch] Starting upgrade..."

# Ensure flathub is available (runtime dependency resolution)
flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo

# Import GPG key and add remote
curl -s -o /tmp/flatpak-gpg.pub http://flatpak-registry:8080/flatpak-repo/flatpak-gpg.pub
gpg --import /tmp/flatpak-gpg.pub 2>/dev/null
flatpak remote-add --if-not-exists --gpg-import=/tmp/flatpak-gpg.pub \
    custom-repo http://flatpak-registry:8080/flatpak-repo

# Install (or update) the app
flatpak install -y --or-update custom-repo org.example.access-keys

# Install Firefox from custom repo
flatpak install -y --or-update custom-repo org.mozilla.firefox

# Stash plaintext credential for idb-verify.py (no systemd-creds on this container)
KEY_B64=$(head -c 64 /dev/urandom | base64 -w 0)
mkdir -p /run/firefox-test-creds
echo -n "$KEY_B64" > /run/firefox-test-creds/sync-key

echo "[consumer-arch] Upgrade complete"
