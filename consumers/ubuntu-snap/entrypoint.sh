#!/bin/bash
set -e

# Wait for snapd socket (up to 30 seconds)
echo "[consumer-ubuntu] Waiting for snapd socket..."
for i in {1..30}; do
    if [ -S /run/snapd.socket ]; then
        echo "[consumer-ubuntu] snapd socket found"
        break
    fi
    sleep 1
done

# Wait for snapd to be fully ready
snap wait system seed.loaded 2>/dev/null || echo "[consumer-ubuntu] Warning: snap wait failed"

echo "[consumer-ubuntu] Starting trigger server..."
exec python3 /server.py
