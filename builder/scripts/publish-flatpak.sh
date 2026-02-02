#!/bin/bash
set -e

echo "=========================================="
echo "Publishing to Flatpak registry"
echo "=========================================="

BINARY="/output/access-keys"
APP_ID="org.example.access-keys"
REGISTRY="http://flatpak-registry:8080"

# Wait for registry to be available
timeout 60 bash -c 'until curl -s http://flatpak-registry:8080/ > /dev/null; do sleep 1; done'

# Generate GPG key for signing (non-interactive)
echo "Generating GPG key for signing..."
gpg --batch --gen-key <<EOF
Key-Type: RSA
Key-Length: 2048
Name-Real: Flatpak Test
Name-Email: flatpak@test.local
Expire-Date: 0
%no-protection
%commit
EOF

# Export public key
echo "Exporting GPG public key..."
gpg --export --armor flatpak@test.local > /tmp/flatpak-gpg.pub

# Upload public key to registry
curl --upload-file /tmp/flatpak-gpg.pub ${REGISTRY}/flatpak-repo/flatpak-gpg.pub

# Initialize flatpak build directory
echo "Building flatpak application..."
flatpak build-init /tmp/flatpak-app ${APP_ID} org.freedesktop.Sdk org.freedesktop.Platform 23.08

# Copy binary into flatpak
mkdir -p /tmp/flatpak-app/files/bin
cp ${BINARY} /tmp/flatpak-app/files/bin/access-keys
chmod +x /tmp/flatpak-app/files/bin/access-keys

# Copy appstream metadata to suppress warnings
mkdir -p /tmp/flatpak-app/files/share/metainfo
cp /scripts/org.example.access-keys.metainfo.xml /tmp/flatpak-app/files/share/metainfo/

# Finish the build
flatpak build-finish /tmp/flatpak-app --command=access-keys

# Initialize OSTree repository
echo "Creating signed OSTree repository..."
ostree init --mode=archive-z2 --repo=/tmp/flatpak-repo

# Export to repository with GPG signing
flatpak build-export --gpg-sign=flatpak@test.local /tmp/flatpak-repo /tmp/flatpak-app stable

# Generate signed summary file
flatpak build-update-repo --gpg-sign=flatpak@test.local /tmp/flatpak-repo

# Upload repository contents to registry
echo "Uploading repository to registry..."
cd /tmp/flatpak-repo

# Upload summary and summary.sig
curl --upload-file summary ${REGISTRY}/flatpak-repo/summary
curl --upload-file summary.sig ${REGISTRY}/flatpak-repo/summary.sig

# Upload objects directory recursively
find objects -type f | while read -r file; do
    curl --create-dirs --upload-file "$file" "${REGISTRY}/flatpak-repo/$file"
done

# Upload refs directory
find refs -type f | while read -r file; do
    curl --create-dirs --upload-file "$file" "${REGISTRY}/flatpak-repo/$file"
done

# Upload config if present
if [ -f config ]; then
    curl --upload-file config ${REGISTRY}/flatpak-repo/config
fi

echo "Flatpak publish complete"
echo ""
