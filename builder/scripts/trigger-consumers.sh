#!/bin/bash
set -e

echo "=========================================="
echo "Triggering all consumers"
echo "=========================================="

CONSUMERS=(
    "consumer-arch:9000"
    "host.containers.internal:9002"   # VM via host port forward
    "consumer-debian:9000"
    "consumer-redhat:9000"
)

# Wait a bit for consumers to be ready
sleep 5

# Trigger all consumers in parallel
for consumer in "${CONSUMERS[@]}"; do
    echo "Triggering ${consumer}..."
    (
        timeout 10 bash -c "until curl -s http://${consumer}/health > /dev/null; do sleep 1; done" || true
        curl -X POST http://${consumer}/trigger &
    )
done

# Wait for all background jobs
wait

echo "All consumers triggered"
echo ""
