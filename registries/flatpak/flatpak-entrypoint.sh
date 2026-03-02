#!/bin/bash
nginx -g 'daemon on;'
REPO_DIR=/var/www/html/flatpak-repo
while true; do
    TARBALL="${REPO_DIR}/repo-update.tar.gz"
    if [ -f "$TARBALL" ]; then
        tar -xzf "$TARBALL" -C "$REPO_DIR"
        rm -f "$TARBALL"
    fi
    sleep 1
done
