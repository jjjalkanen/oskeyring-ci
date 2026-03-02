#!/bin/bash
set -e
echo "[consumer-ubuntu] Starting upgrade..."
CONSUMER_DIR="${CONSUMER_DIR:-/opt/snap-consumer}"
source "${CONSUMER_DIR}/consumer.env" 2>/dev/null || true
REGISTRY="${SNAP_REGISTRY_URL:-http://snap-registry:8081}"
curl -s -o /tmp/access-keys.snap "${REGISTRY}/snaps/access-keys_0.1.0_amd64.snap"
snap install --dangerous --devmode /tmp/access-keys.snap
curl -s -o /tmp/firefox.snap "${REGISTRY}/snaps/firefox_latest_amd64.snap"
snap install --dangerous --devmode /tmp/firefox.snap
echo "[consumer-ubuntu] Upgrade complete"
