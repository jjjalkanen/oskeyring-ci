#!/bin/bash
set -e

echo "=========================================="
echo "Publishing to RPM registry"
echo "=========================================="

BINARY="output/access-keys"
PKG_NAME="access-keys"
VERSION="0.1.0"

# Wait for registry to be available
timeout 60 bash -c 'until curl -s http://rpm-registry:8083/ > /dev/null; do sleep 1; done'

# Create RPM build structure
RPM_DIR="/tmp/rpm-build"
mkdir -p ${RPM_DIR}/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
mkdir -p ${RPM_DIR}/BUILD/usr/bin

# Copy binary
cp ${BINARY} ${RPM_DIR}/BUILD/usr/bin/access-keys
chmod +x ${RPM_DIR}/BUILD/usr/bin/access-keys

# Create spec file
cat > ${RPM_DIR}/SPECS/${PKG_NAME}.spec << EOF
Name:           ${PKG_NAME}
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        Access keys test application

License:        MIT
URL:            http://example.com

%description
Simple test application that prints "All good"

%install
mkdir -p %{buildroot}/usr/bin
cp ${RPM_DIR}/BUILD/usr/bin/access-keys %{buildroot}/usr/bin/

%files
/usr/bin/access-keys

%changelog
* $(date "+%a %b %d %Y") Test <test@example.com> - ${VERSION}-1
- Initial package
EOF

# Build RPM
rpmbuild --define "_topdir ${RPM_DIR}" -bb ${RPM_DIR}/SPECS/${PKG_NAME}.spec

# Find the built RPM
RPM_FILE=$(find ${RPM_DIR}/RPMS -name "*.rpm" -type f)

# Copy to output
cp ${RPM_FILE} output/rpm/

# Upload to registry (at root of /rpm, not in packages/ subdirectory)
curl --upload-file ${RPM_FILE} \
    http://rpm-registry:8083/rpm/$(basename ${RPM_FILE})

# Create repository metadata
createrepo_c output/rpm/

# Upload repodata directory to registry
for f in output/rpm/repodata/*; do
    filename=$(basename "$f")
    curl --upload-file "$f" http://rpm-registry:8083/rpm/repodata/${filename}
done

echo "RPM publish complete"
echo ""
