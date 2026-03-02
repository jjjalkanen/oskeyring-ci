#!/bin/bash
set -e

echo "=========================================="
echo "Publishing Firefox to RPM registry"
echo "=========================================="

TARBALL="/home/builder/output/firefox-rhel9.tar.xz"

# Wait for registry to be available
timeout 60 bash -c 'until curl -s http://rpm-registry:8083/ > /dev/null; do sleep 1; done'

# Extract Firefox version from tarball
FIREFOX_VERSION=$(tar -xOf "${TARBALL}" firefox/application.ini 2>/dev/null \
    | grep "^Version=" | head -1 | cut -d= -f2 || true)
[ -z "${FIREFOX_VERSION}" ] && FIREFOX_VERSION="0.0.0"
# RPM Version field must not contain hyphens; strip alpha/beta suffixes
FIREFOX_VERSION_RPM=$(echo "${FIREFOX_VERSION}" | sed 's/[^0-9.].*$//' | sed 's/\.$//')
[ -z "${FIREFOX_VERSION_RPM}" ] && FIREFOX_VERSION_RPM="0.0.0"
echo "Firefox version: ${FIREFOX_VERSION} (RPM: ${FIREFOX_VERSION_RPM})"

# Extract tarball
EXTRACT_DIR="/tmp/firefox-rpm-extract"
mkdir -p "${EXTRACT_DIR}"
echo "Extracting Firefox tarball..."
tar -xf "${TARBALL}" -C "${EXTRACT_DIR}"

# Create RPM build structure
RPM_DIR="/tmp/firefox-rpm-build"
mkdir -p "${RPM_DIR}"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
mkdir -p "${RPM_DIR}/BUILD/usr/lib/firefox"
mkdir -p "${RPM_DIR}/BUILD/usr/bin"

# Copy Firefox files into BUILD dir
echo "Copying Firefox files into RPM build dir..."
cp -a "${EXTRACT_DIR}/firefox/." "${RPM_DIR}/BUILD/usr/lib/firefox/"

# Create spec file
cat > "${RPM_DIR}/SPECS/firefox.spec" << SPEC
Name:           firefox
Version:        ${FIREFOX_VERSION_RPM}
Release:        1%{?dist}
Summary:        Mozilla Firefox Web Browser

License:        MPL-2.0
URL:            https://www.mozilla.org/firefox/

%description
Mozilla Firefox is a free and open-source web browser developed by Mozilla.

%install
mkdir -p %{buildroot}/usr/lib/firefox
cp -a ${RPM_DIR}/BUILD/usr/lib/firefox/. %{buildroot}/usr/lib/firefox/
mkdir -p %{buildroot}/usr/bin
ln -sf /usr/lib/firefox/firefox %{buildroot}/usr/bin/firefox

%files
%dir /usr/lib/firefox
/usr/lib/firefox/*
/usr/bin/firefox

%changelog
* $(date "+%a %b %d %Y") Test <test@example.com> - ${FIREFOX_VERSION_RPM}-1
- Firefox package
SPEC

# Build RPM (QA_RPATHS: Firefox's libonnxruntime.so has a broken RPATH)
echo "Building Firefox RPM..."
QA_RPATHS=0x0002 rpmbuild --define "_topdir ${RPM_DIR}" -bb "${RPM_DIR}/SPECS/firefox.spec"

# Find the built RPM
RPM_FILE=$(find "${RPM_DIR}/RPMS" -name "firefox-*.rpm" -type f)

# Copy to output/rpm alongside access-keys RPM
cp "${RPM_FILE}" output/rpm/

# Upload to registry
curl --upload-file "${RPM_FILE}" \
    "http://rpm-registry:8083/rpm/$(basename ${RPM_FILE})"

# Regenerate repo metadata covering BOTH access-keys and Firefox
# output/rpm/ already has access-keys RPM from publish-rpm.sh
createrepo_c output/rpm/

# Upload updated repodata (overwrites the access-keys-only metadata)
for f in output/rpm/repodata/*; do
    filename=$(basename "$f")
    curl --upload-file "$f" "http://rpm-registry:8083/rpm/repodata/${filename}"
done

echo "Firefox RPM publish complete"
echo ""
