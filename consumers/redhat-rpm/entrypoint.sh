#!/bin/bash
set -e

# Wait for systemd to be ready (up to 30 seconds)
echo "[consumer-redhat] Waiting for systemd to be ready..."
for i in {1..30}; do
    state=$(systemctl is-system-running 2>/dev/null || echo "unknown")
    if [ "$state" = "running" ] || [ "$state" = "degraded" ]; then
        echo "[consumer-redhat] systemd is ready (state: $state)"
        break
    fi
    sleep 1
done

echo "[consumer-redhat] Starting trigger server..."
exec python3 /server.py
