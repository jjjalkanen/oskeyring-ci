#!/bin/bash
set -e

declare -A CONSUMER_ENDPOINTS=(
    [consumer-arch]="consumer-arch:9000"
    [consumer-debian]="host.containers.internal:9003"
    [consumer-redhat]="consumer-redhat:9000"
    [consumer-ubuntu]="host.containers.internal:9002"
)

# Reverse lookup: endpoint → consumer name
declare -A ENDPOINT_NAMES
for name in "${!CONSUMER_ENDPOINTS[@]}"; do
    ENDPOINT_NAMES[${CONSUMER_ENDPOINTS[$name]}]="$name"
done

if [ -n "${ENABLED_CONSUMERS:-}" ]; then
    IFS=',' read -ra ENABLED <<< "$ENABLED_CONSUMERS"
else
    ENABLED=(consumer-arch consumer-debian consumer-redhat consumer-ubuntu)
fi

CONSUMERS=()
for name in "${ENABLED[@]}"; do
    CONSUMERS+=("${CONSUMER_ENDPOINTS[$name]}")
done

COLLECTOR_URL="http://localhost:9999/report"

report_failure() {
    local consumer_name="$1"
    local error_msg="$2"
    echo "  Reporting failure for ${consumer_name} to results collector"
    curl -s -X POST -H 'Content-Type: application/json' \
        -d "{\"consumer\": \"${consumer_name}\", \"status\": \"error\", \"output\": \"\", \"error\": \"${error_msg}\"}" \
        "$COLLECTOR_URL" >/dev/null 2>&1 || true
}

echo "Checking consumer health..."
for consumer in "${CONSUMERS[@]}"; do
    name="${ENDPOINT_NAMES[$consumer]}"
    echo "  Checking ${consumer} (${name})..."
    if timeout 90 bash -c "until curl -s http://${consumer}/health > /dev/null 2>&1; do sleep 1; done"; then
        echo "  ${name} is healthy"
    else
        echo "  ERROR: ${name} health check timed out"
        report_failure "$name" "Health check timed out after 90s"
    fi
done
echo ""

echo "Triggering consumers (in parallel)..."
TRIGGER_PIDS=()
for consumer in "${CONSUMERS[@]}"; do
    name="${ENDPOINT_NAMES[$consumer]}"
    echo "  Triggering ${name}..."
    (
        if ! curl -s --max-time 600 -X POST "http://${consumer}/trigger"; then
            echo "  ERROR: trigger failed for ${name}"
            report_failure "$name" "Trigger POST failed"
        fi
    ) &
    TRIGGER_PIDS+=($!)
done

for pid in "${TRIGGER_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done
echo "All consumers triggered"
