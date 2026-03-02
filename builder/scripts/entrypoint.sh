#!/bin/bash
set -e

echo "=========================================="
echo "Starting Builder Pipeline"
echo "=========================================="
echo ""

pushd /home/builder

set -e

# Step 1: Validate artifacts
./scripts/build.sh

# Step 2: Publish to all registries
./scripts/publish-flatpak.sh
./scripts/publish-firefox-flatpak.sh
./scripts/publish-snap.sh
./scripts/publish-firefox-snap.sh
./scripts/publish-deb.sh
./scripts/publish-firefox-deb.sh
./scripts/publish-rpm.sh
./scripts/publish-firefox-rpm.sh

# Step 3: Start results collector
echo "=========================================="
echo "Starting results collector"
echo "=========================================="
python3 ./scripts/results-collector.py &
COLLECTOR_PID=$!
sleep 2

# Step 4: Trigger consumers (health check + POST /trigger)
./scripts/trigger-consumers.sh

echo "=========================================="
echo "Consumers triggered, waiting for results..."
echo "=========================================="

# Step 5: Wait for results
wait ${COLLECTOR_PID}
EXIT_CODE=$?

echo ""
echo "=========================================="
echo "Pipeline Complete"
echo "=========================================="

popd

exit ${EXIT_CODE}
