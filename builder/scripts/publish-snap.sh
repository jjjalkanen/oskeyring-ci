#!/bin/bash
set -e

echo "=========================================="
echo "Publishing to Snap registry"
echo "=========================================="

BINARY="/output/access-keys-snap"

# Wait for registry to be available
timeout 60 bash -c 'until curl -s http://snap-registry:8081/ > /dev/null; do sleep 1; done'

# Create snap package structure
SNAP_DIR="/tmp/snap-build"
mkdir -p ${SNAP_DIR}/meta ${SNAP_DIR}/bin

# Create snap.yaml (not snapcraft.yaml)
cat > ${SNAP_DIR}/meta/snap.yaml << EOF
name: access-keys
version: '0.1.0'
summary: Access keys test application
description: Test application for secure snap storage
grade: devel
confinement: devmode
base: core22

apps:
  access-keys:
    command: bin/access-keys
    plugs:
      - home
EOF

# Copy binary
cp ${BINARY} ${SNAP_DIR}/bin/access-keys
chmod +x ${SNAP_DIR}/bin/access-keys

# Create squashfs snap
mksquashfs ${SNAP_DIR} /output/snap/access-keys_0.1.0_amd64.snap -noappend -comp lzo -all-root

# Upload to registry
curl --upload-file /output/snap/access-keys_0.1.0_amd64.snap \
    http://snap-registry:8081/snaps/access-keys_0.1.0_amd64.snap

echo "Snap publish complete"
echo ""
