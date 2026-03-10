#!/bin/bash
set -e

echo "=========================================="
echo "Publishing Firefox to Debian registry"
echo "=========================================="

REGISTRY="http://deb-registry:8082"
TARBALL="/home/builder/output/firefox.tar.xz"

# Wait for registry to be available
timeout 60 bash -c 'until curl -s http://deb-registry:8082/ > /dev/null; do sleep 1; done'

# Extract Firefox version from tarball
FIREFOX_VERSION=$(tar -xOf "${TARBALL}" firefox/application.ini 2>/dev/null \
    | grep "^Version=" | head -1 | cut -d= -f2 || true)
[ -z "${FIREFOX_VERSION}" ] && FIREFOX_VERSION="0.0.0"
echo "Firefox version: ${FIREFOX_VERSION}"

# Extract tarball
EXTRACT_DIR="/tmp/firefox-deb-extract"
mkdir -p "${EXTRACT_DIR}"
echo "Extracting Firefox tarball..."
tar -xf "${TARBALL}" -C "${EXTRACT_DIR}"

# Create deb package structure
DEB_DIR="/tmp/firefox-deb-build/firefox_${FIREFOX_VERSION}"
mkdir -p "${DEB_DIR}/DEBIAN"
mkdir -p "${DEB_DIR}/usr/lib/firefox"
mkdir -p "${DEB_DIR}/usr/bin"

# Create control file (no system library deps to avoid internet resolution issues)
cat > "${DEB_DIR}/DEBIAN/control" << EOF
Package: firefox
Version: ${FIREFOX_VERSION}
Section: web
Priority: optional
Architecture: amd64
Maintainer: Test <test@example.com>
Description: Mozilla Firefox Web Browser
 Firefox is a free and open-source web browser developed by Mozilla.
EOF

# Include upstream postinst (process Makefile $$ escaping and substitute PKG_NAME)
sed 's/\$\$/$/g; s/${PKG_NAME}/firefox/g' \
    /home/builder/firefox/browser/installer/linux/app/debian/postinst.in \
    > "${DEB_DIR}/DEBIAN/postinst"
chmod 755 "${DEB_DIR}/DEBIAN/postinst"

# Copy Firefox files
echo "Copying Firefox files into deb structure..."
cp -a "${EXTRACT_DIR}/firefox/." "${DEB_DIR}/usr/lib/firefox/"

# Create /usr/bin/firefox symlink pointing to the bundled binary
ln -sf /usr/lib/firefox/firefox "${DEB_DIR}/usr/bin/firefox"

# Build deb package
DEB_FILE="output/deb/firefox_${FIREFOX_VERSION}_amd64.deb"
echo "Building .deb package..."
dpkg-deb --build "${DEB_DIR}" "${DEB_FILE}"

# Upload .deb to registry pool
echo "Uploading firefox .deb to registry..."
curl --upload-file "${DEB_FILE}" \
    "${REGISTRY}/debian/pool/main/firefox_${FIREFOX_VERSION}_amd64.deb"

# Regenerate Packages covering BOTH access-keys and Firefox.
# publish-deb.sh already placed access-keys .deb in /tmp/apt-repo/pool/main/
cp "${DEB_FILE}" /tmp/apt-repo/pool/main/
cd /tmp/apt-repo
dpkg-scanpackages pool/main /dev/null > Packages
gzip -9c Packages > Packages.gz

# Upload updated Packages files
curl --upload-file Packages "${REGISTRY}/debian/dists/stable/main/binary-amd64/Packages"
curl --upload-file Packages.gz "${REGISTRY}/debian/dists/stable/main/binary-amd64/Packages.gz"

# Regenerate Release file with updated checksums
cp Packages Packages.gz dists/stable/main/binary-amd64/

cat > dists/stable/Release << EOF
Origin: Custom Repository
Label: Custom
Suite: stable
Codename: stable
Architectures: amd64
Components: main
Description: Custom APT Repository
Date: $(date -Ru)
EOF

{
    echo "MD5Sum:"
    for f in main/binary-amd64/Packages main/binary-amd64/Packages.gz; do
        size=$(stat -c %s dists/stable/$f)
        md5=$(md5sum dists/stable/$f | cut -d' ' -f1)
        printf " %s %d %s\n" "$md5" "$size" "$f"
    done
    echo "SHA256:"
    for f in main/binary-amd64/Packages main/binary-amd64/Packages.gz; do
        size=$(stat -c %s dists/stable/$f)
        sha=$(sha256sum dists/stable/$f | cut -d' ' -f1)
        printf " %s %d %s\n" "$sha" "$size" "$f"
    done
} >> dists/stable/Release

curl --upload-file dists/stable/Release "${REGISTRY}/debian/dists/stable/Release"

echo "Firefox Debian package publish complete"
echo ""
