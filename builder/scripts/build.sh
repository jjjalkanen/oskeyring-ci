#!/bin/bash
set -e

echo "=========================================="
echo "Validating pre-built artifacts"
echo "=========================================="

OUTPUT_DIR="/home/builder/output"

ARTIFACTS=(
    "access-keys"
    "access-keys-snap"
    "access-keys-flatpak"
    "access-keys-systemd"
    "firefox.tar.xz"
)

MISSING=0
for artifact in "${ARTIFACTS[@]}"; do
    if [ ! -f "$OUTPUT_DIR/$artifact" ]; then
        echo "MISSING: $OUTPUT_DIR/$artifact"
        MISSING=1
    else
        SIZE=$(stat -c%s "$OUTPUT_DIR/$artifact")
        echo "  OK: $artifact (${SIZE} bytes)"
    fi
done

if [ $MISSING -ne 0 ]; then
    echo ""
    echo "ERROR: Missing artifacts. Run host build first (scripts/run-orchestration.sh)"
    exit 1
fi

# Create subdirectories needed by publish scripts
mkdir -p "$OUTPUT_DIR"/{deb,rpm,snap,flatpak}

echo ""
echo "All artifacts validated. Ready to publish."
echo ""
