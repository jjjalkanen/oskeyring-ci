#!/bin/bash
TIMEOUT=${TIMEOUT:-120}
PORT=${VM_TRIGGER_PORT:-9002}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="${VM_LOG_FILE:-$SCRIPT_DIR/../vm/logs/console.log}"

echo "Waiting for VM health check on localhost:$PORT..."

start_time=$(date +%s)
last_log_line=""

while true; do
    elapsed=$(($(date +%s) - start_time))

    # Show boot progress from serial console
    if [ -f "$LOG_FILE" ]; then
        current_line=$(tail -1 "$LOG_FILE" 2>/dev/null | grep -o '\[cloud-init\].*' || true)
        if [ -n "$current_line" ] && [ "$current_line" != "$last_log_line" ]; then
            echo "  $current_line"
            last_log_line="$current_line"
        fi
    fi

    if [ $elapsed -ge $TIMEOUT ]; then
        echo "ERROR: VM health check timeout after ${TIMEOUT}s"
        if [ -f "$LOG_FILE" ]; then
            echo ""
            echo "Last 10 lines of console log:"
            tail -10 "$LOG_FILE"
        fi
        exit 1
    fi

    if curl -s --connect-timeout 2 "http://localhost:$PORT/health" 2>/dev/null | grep -q "OK"; then
        echo "VM is healthy! (${elapsed}s)"
        exit 0
    fi

    sleep 2
done
