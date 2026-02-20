#!/bin/bash
set -e

echo "=========================================="
echo "Publishing to Debian registry"
echo "=========================================="

BINARY="output/access-keys-systemd"
PKG_NAME="access-keys"
VERSION="0.1.0"
REGISTRY="http://deb-registry:8082"

# Wait for registry to be available
timeout 60 bash -c 'until curl -s http://deb-registry:8082/ > /dev/null; do sleep 1; done'

# Create deb package structure
DEB_DIR="/tmp/deb-build/${PKG_NAME}_${VERSION}"
mkdir -p ${DEB_DIR}/DEBIAN
mkdir -p ${DEB_DIR}/usr/bin

# Create control file
cat > ${DEB_DIR}/DEBIAN/control << EOF
Package: ${PKG_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Test <test@example.com>
Description: Access keys test application
 Simple test application that prints "All good"
EOF

# Copy binary
cp ${BINARY} ${DEB_DIR}/usr/bin/access-keys
chmod +x ${DEB_DIR}/usr/bin/access-keys

# Build deb package
dpkg-deb --build ${DEB_DIR} output/deb/${PKG_NAME}_${VERSION}_amd64.deb

# Upload .deb to pool
curl --upload-file output/deb/${PKG_NAME}_${VERSION}_amd64.deb \
    ${REGISTRY}/debian/pool/main/${PKG_NAME}_${VERSION}_amd64.deb

# Create local repository structure with correct paths
mkdir -p /tmp/apt-repo/pool/main
cp output/deb/${PKG_NAME}_${VERSION}_amd64.deb /tmp/apt-repo/pool/main/

# Generate Packages file with correct pool/main paths
cd /tmp/apt-repo
dpkg-scanpackages pool/main /dev/null > Packages
gzip -9c Packages > Packages.gz

# Upload Packages files
curl --upload-file Packages ${REGISTRY}/debian/dists/stable/main/binary-amd64/Packages
curl --upload-file Packages.gz ${REGISTRY}/debian/dists/stable/main/binary-amd64/Packages.gz

# Create Release file structure
mkdir -p dists/stable/main/binary-amd64
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

# Add checksums to Release
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

# Upload Release file
curl --upload-file dists/stable/Release ${REGISTRY}/debian/dists/stable/Release

echo "Debian package publish complete"
echo ""
