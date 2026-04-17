#!/bin/bash
set -e

declare -A CONSUMER_ENDPOINTS=(
    [consumer-arch]="consumer-arch:9000"
    [consumer-debian]="host.containers.internal:9003"
    [consumer-redhat]="consumer-redhat:9000"
    [consumer-ubuntu]="host.containers.internal:9002"
)

if [ -n "${ENABLED_CONSUMERS:-}" ]; then
    IFS=',' read -ra ENABLED <<< "$ENABLED_CONSUMERS"
else
    ENABLED=(consumer-arch consumer-debian consumer-redhat consumer-ubuntu)
fi

CONSUMERS=()
for name in "${ENABLED[@]}"; do
    CONSUMERS+=("${CONSUMER_ENDPOINTS[$name]}")
done

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
