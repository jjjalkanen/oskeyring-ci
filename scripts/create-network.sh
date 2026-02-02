#!/bin/bash
set -e

NETWORK_NAME="podman-build-network"

echo "Creating Podman network: ${NETWORK_NAME}"

# Check if network already exists
if podman network exists ${NETWORK_NAME}; then
    echo "Network ${NETWORK_NAME} already exists"
else
    podman network create ${NETWORK_NAME}
    echo "Network ${NETWORK_NAME} created successfully"
fi

# Show network details
podman network inspect ${NETWORK_NAME}
