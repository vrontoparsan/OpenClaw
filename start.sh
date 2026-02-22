#!/bin/sh
echo "=== Starting OpenClaw Gateway ==="
echo "Running as: $(id)"
echo "STATE_DIR: ${OPENCLAW_STATE_DIR:-/home/node/.openclaw}"

STATE="${OPENCLAW_STATE_DIR:-/home/node/.openclaw}"

# If running as root: fix /data volume permissions, write initial files, then exec as node
if [ "$(id -u)" = "0" ]; then
    echo "Root detected — fixing /data volume permissions..."

    # Make /data writable
    mkdir -p /data
    chown node:node /data

    # Pre-create state dirs
    mkdir -p "$STATE/devices" "$STATE/credentials"

    # Write devices/paired.json (preserve existing approved devices)
    node -e "
        const fs=require('fs');
        const f='$STATE/devices/paired.json';
        let arr=[];
        try{arr=JSON.parse(fs.readFileSync(f,'utf8'))||[];}catch(e){}
        fs.writeFileSync(f,JSON.stringify(arr));
        console.log('Devices paired.json initialized, count:', arr.length);
    " 2>&1 || true

    # Write telegram allowFrom if TELEGRAM_ALLOW_FROM env var is set
    if [ -n "$TELEGRAM_ALLOW_FROM" ]; then
        node -e "
            const ids = process.env.TELEGRAM_ALLOW_FROM.split(',').map(id => id.trim());
            const data = JSON.stringify({version:1,allowFrom:ids},null,2)+'\n';
            const f = '$STATE/credentials/telegram-default-allowFrom.json';
            require('fs').writeFileSync(f, data);
            console.log('Telegram allowFrom written:', ids);
        " 2>&1 || true
    fi

    # Fix ownership AFTER creating files so node user can modify them
    chown -R node:node "$STATE"

    echo "Permissions fixed. Switching to node user..."
    exec su node -s /bin/sh -- "$0" "$@"
fi

# === Running as node user from here ===
echo "Gateway starting as node user..."

# Start gateway in background
node openclaw.mjs gateway --allow-unconfigured --bind lan --port 18789 &
GATEWAY_PID=$!
echo "Gateway PID: $GATEWAY_PID"

# Auto-approve device pairing loop
(
    sleep 15
    echo "=== Auto-approve attempt ==="
    node openclaw.mjs devices approve --latest 2>&1 || true

    while kill -0 $GATEWAY_PID 2>/dev/null; do
        sleep 20
        echo "=== Auto-approve ==="
        node openclaw.mjs devices approve --latest 2>&1 || true
    done
) &

wait $GATEWAY_PID
