#!/bin/bash
set -e

echo "=========================================="
echo "Building access-keys application"
echo "=========================================="

cd /build

# Build default binary (for flatpak, deb, rpm)
echo "Building default Rust binary..."
cargo build --release
cp target/release/access-keys /output/access-keys

# Build snap-specific binary with snap feature
echo "Building Snap-specific binary..."
cargo build --release --features snap
mkdir -p /output/snap
cp target/release/access-keys /output/access-keys-snap

# Build flatpak-specific binary with flatpak feature
echo "Building Flatpak-specific binary..."
cargo build --release --features flatpak
mkdir -p /output/flatpak
cp target/release/access-keys /output/access-keys-flatpak

# Create output directory structure
mkdir -p /output/{deb,rpm}

echo "Build complete:"
echo "  - Default binary: /output/access-keys"
echo "  - Snap binary: /output/access-keys-snap"
echo "  - Flatpak binary: /output/access-keys-flatpak"
echo ""
