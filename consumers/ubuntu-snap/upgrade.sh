#!/bin/bash
set -e
echo "[consumer-ubuntu] Starting upgrade..."
REGISTRY="${SNAP_REGISTRY_URL:-http://snap-registry:8081}"
curl -s -o /tmp/access-keys.snap "${REGISTRY}/snaps/access-keys_0.1.0_amd64.snap"
snap install --dangerous --devmode /tmp/access-keys.snap
curl -s -o /tmp/firefox.snap "${REGISTRY}/snaps/firefox_latest_amd64.snap"
snap install --dangerous --devmode /tmp/firefox.snap
echo "[consumer-ubuntu] Upgrade complete"
