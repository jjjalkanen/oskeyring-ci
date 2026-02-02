#!/bin/bash
set -e

echo "[consumer-ubuntu] Installing access-keys from snap..."

# Wait for registry to be available
timeout 60 bash -c 'until curl -s http://snap-registry:8081/ > /dev/null; do sleep 1; done'

# Download snap
curl -o /tmp/access-keys.snap http://snap-registry:8081/snaps/access-keys_0.1.0_amd64.snap

# Install the snap (devmode for unsigned snap)
snap install --dangerous --devmode /tmp/access-keys.snap

# Ensure snap bin directory is in PATH
export PATH="/snap/bin:$PATH"
echo 'export PATH="/snap/bin:$PATH"' >> /etc/profile

echo "[consumer-ubuntu] Installation complete"
