#!/bin/sh
echo "=== Starting OpenClaw Gateway ==="
echo "STATE_DIR: $OPENCLAW_STATE_DIR"

# Start gateway in background
node openclaw.mjs gateway --allow-unconfigured --bind lan --port 18789 &
GATEWAY_PID=$!
echo "Gateway PID: $GATEWAY_PID"

# Debug device management after gateway starts
(
    sleep 15
    echo "=== Checking openclaw devices command ==="
    node openclaw.mjs devices list 2>&1
    echo "=== Trying approve --latest ==="
    node openclaw.mjs devices approve --latest 2>&1
    echo "=== Done ==="

    # Keep trying every 20s
    while kill -0 $GATEWAY_PID 2>/dev/null; do
        sleep 20
        echo "=== Auto-approve attempt ==="
        node openclaw.mjs devices approve --latest 2>&1 || true
    done
) &

wait $GATEWAY_PID
