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

echo "[consumer-arch] Upgrade complete"
