#!/bin/bash
set -e

CONSUMERS=(
    "consumer-arch:9000"
    "host.containers.internal:9002"
    "consumer-debian:9000"
    "consumer-redhat:9000"
)

echo "Checking consumer health..."
for consumer in "${CONSUMERS[@]}"; do
    echo "  Checking ${consumer}..."
    if timeout 90 bash -c "until curl -s http://${consumer}/health > /dev/null 2>&1; do sleep 1; done"; then
        echo "  ${consumer} is healthy"
    else
        echo "  Warning: ${consumer} health check timed out (continuing anyway)"
    fi
done
echo ""

echo "Triggering consumers..."
for consumer in "${CONSUMERS[@]}"; do
    echo "  Triggering ${consumer}..."
    curl -s -X POST "http://${consumer}/trigger" || echo "  Warning: trigger failed for ${consumer}"
done
echo "All consumers triggered"
