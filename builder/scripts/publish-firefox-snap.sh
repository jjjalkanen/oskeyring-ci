#!/bin/bash
set -e

echo "=========================================="
echo "Publishing Firefox to Snap registry"
echo "=========================================="

REGISTRY="http://snap-registry:8081"
TARBALL="/home/builder/output/firefox.tar.xz"

# Wait for registry to be available
timeout 60 bash -c 'until curl -s http://snap-registry:8081/ > /dev/null; do sleep 1; done'

# Extract Firefox version from tarball
FIREFOX_VERSION=$(tar -xOf "${TARBALL}" firefox/application.ini 2>/dev/null \
    | grep "^Version=" | head -1 | cut -d= -f2 || true)
[ -z "${FIREFOX_VERSION}" ] && FIREFOX_VERSION="0.0.0"
echo "Firefox version: ${FIREFOX_VERSION}"

# Extract tarball
EXTRACT_DIR="/tmp/firefox-snap-extract"
mkdir -p "${EXTRACT_DIR}"
echo "Extracting Firefox tarball..."
tar -xf "${TARBALL}" -C "${EXTRACT_DIR}"

# Create snap package structure
SNAP_DIR="/tmp/firefox-snap-build"
mkdir -p "${SNAP_DIR}/meta"
mkdir -p "${SNAP_DIR}/lib/firefox"
mkdir -p "${SNAP_DIR}/bin"

# Create snap.yaml
cat > "${SNAP_DIR}/meta/snap.yaml" << EOF
name: firefox
version: '${FIREFOX_VERSION}'
summary: Mozilla Firefox Web Browser
description: Firefox is a free and open-source web browser developed by Mozilla.
grade: devel
confinement: devmode
base: core22

apps:
  firefox:
    command: bin/firefox
  geckodriver:
    command: bin/geckodriver
EOF

# Copy Firefox files
echo "Copying Firefox files into snap structure..."
cp -a "${EXTRACT_DIR}/firefox/." "${SNAP_DIR}/lib/firefox/"

# Include geckodriver
cp /home/builder/output/geckodriver "${SNAP_DIR}/lib/firefox/geckodriver"
chmod +x "${SNAP_DIR}/lib/firefox/geckodriver"

# Create geckodriver wrapper script
cat > "${SNAP_DIR}/bin/geckodriver" << 'GECKOWRAPPER'
#!/bin/bash
exec "$SNAP/lib/firefox/geckodriver" "$@"
GECKOWRAPPER
chmod +x "${SNAP_DIR}/bin/geckodriver"

# Create wrapper script
cat > "${SNAP_DIR}/bin/firefox" << 'WRAPPER'
#!/bin/bash
exec "$SNAP/lib/firefox/firefox" "$@"
WRAPPER
chmod +x "${SNAP_DIR}/bin/firefox"

# Copy install hook from upstream Firefox installer template.
#
# Layout translation: in the snapcraft *source* layout, hooks live at
# snap/hooks/<name>.  In the snap *runtime* format (the .snap squashfs),
# they live at meta/hooks/<name>.  Our publish script builds the runtime
# format directly with mksquashfs (we don't use snapcraft), so we place
# the hook at meta/hooks/install.
#
# Source: firefox/browser/installer/linux/app/snap/hooks/install
mkdir -p "${SNAP_DIR}/meta/hooks"
cp /home/builder/firefox/browser/installer/linux/app/snap/hooks/install \
    "${SNAP_DIR}/meta/hooks/install"
cp /home/builder/firefox/browser/installer/linux/app/snap/hooks/post-refresh \
    "${SNAP_DIR}/meta/hooks/post-refresh"
chmod +x "${SNAP_DIR}/meta/hooks/install" "${SNAP_DIR}/meta/hooks/post-refresh"

# Create squashfs snap, published as firefox_latest_amd64.snap for stable URL
SNAP_FILE="output/snap/firefox_latest_amd64.snap"
echo "Creating Firefox snap..."
mksquashfs "${SNAP_DIR}" "${SNAP_FILE}" -noappend -comp lzo -all-root

# Upload to registry
curl --upload-file "${SNAP_FILE}" "${REGISTRY}/snaps/firefox_latest_amd64.snap"

echo "Firefox Snap publish complete"
echo ""
