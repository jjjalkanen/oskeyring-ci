#!/bin/bash
set -e

echo "=========================================="
echo "Building access-keys application"
echo "=========================================="

cd /build

# Build Rust binary
echo "Building Rust binary..."
cargo build --release

# Create output directory structure
mkdir -p /output/{flatpak,snap,deb,rpm}

# Copy binary to output
cp target/release/access-keys /output/access-keys

echo "Build complete: Binary at /output/access-keys"
echo ""
