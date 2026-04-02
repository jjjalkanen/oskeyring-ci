#!/bin/bash
set -e

echo "=========================================="
echo "Starting Builder Pipeline"
echo "=========================================="
echo ""

# Consumer filtering
if [ -n "${ENABLED_CONSUMERS:-}" ]; then
    IFS=',' read -ra _enabled <<< "$ENABLED_CONSUMERS"
else
    _enabled=(consumer-arch consumer-debian consumer-redhat consumer-ubuntu)
fi

is_enabled() {
    local name="$1"
    for c in "${_enabled[@]}"; do [[ "$c" == "$name" ]] && return 0; done
    return 1
}

echo "Enabled consumers: ${_enabled[*]}"
echo ""

pushd /home/builder

set -e

# Step 1: Validate artifacts
./scripts/build.sh

# Step 2: Publish to enabled registries
is_enabled consumer-arch   && { ./scripts/publish-flatpak.sh; ./scripts/publish-firefox-flatpak.sh; } || true
is_enabled consumer-ubuntu && { ./scripts/publish-snap.sh;    ./scripts/publish-firefox-snap.sh; } || true
is_enabled consumer-debian && { ./scripts/publish-deb.sh;     ./scripts/publish-firefox-deb.sh; } || true
is_enabled consumer-redhat && { ./scripts/publish-rpm.sh;     ./scripts/publish-firefox-rpm.sh; } || true

# Step 3: Start results collector and IDB test server
echo "=========================================="
echo "Starting results collector"
echo "=========================================="
python3 ./scripts/results-collector.py &
COLLECTOR_PID=$!

echo "Starting IDB test server on port 8888..."
python3 ./scripts/idb-test-server.py &
IDB_SERVER_PID=$!

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
