#!/bin/bash
set -e

echo "=========================================="
echo "Starting Builder Pipeline"
echo "=========================================="
echo ""

# Step 1: Build
/scripts/build.sh

# Step 2: Publish to all registries
/scripts/publish-flatpak.sh
/scripts/publish-snap.sh
/scripts/publish-deb.sh
/scripts/publish-rpm.sh

# Step 3: Start results collector in background
echo "=========================================="
echo "Starting results collector"
echo "=========================================="
python3 /scripts/results-collector.py &
COLLECTOR_PID=$!

# Wait for collector to be ready
sleep 3

# Step 4: Trigger all consumers
/scripts/trigger-consumers.sh

# Step 5: Wait for results collector to finish
echo "=========================================="
echo "Waiting for test results..."
echo "=========================================="
wait ${COLLECTOR_PID}
EXIT_CODE=$?

echo ""
echo "=========================================="
echo "Pipeline Complete"
echo "=========================================="

exit ${EXIT_CODE}
