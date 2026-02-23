#!/bin/sh
echo "=== Starting OpenClaw Gateway ==="
echo "Running as: $(id)"

STATE="${OPENCLAW_STATE_DIR:-/home/node/.openclaw}"
echo "STATE_DIR: $STATE"

# Create state dirs
mkdir -p "$STATE/devices" "$STATE/credentials"

# Write devices/paired.json - format is Record<string,PairedDevice> (object, not array!)
node -e "
    const fs=require('fs');
    const f='$STATE/devices/paired.json';
    let obj={};
    try{const r=JSON.parse(fs.readFileSync(f,'utf8'));if(r&&typeof r==='object'&&!Array.isArray(r))obj=r;}catch(e){}
    fs.writeFileSync(f,JSON.stringify(obj));
    console.log('Devices paired.json:', Object.keys(obj).length, 'entries');
" 2>&1 || true

# Write telegram allowFrom from env var
if [ -n "\$TELEGRAM_ALLOW_FROM" ]; then
    node -e "
        const ids = process.env.TELEGRAM_ALLOW_FROM.split(',').map(id => id.trim());
        const data = JSON.stringify({version:1,allowFrom:ids},null,2)+'\n';
        require('fs').writeFileSync('$STATE/credentials/telegram-default-allowFrom.json', data);
        console.log('Telegram allowFrom:', ids);
    " 2>&1 || true
fi

# Reset openclaw.json — agent may corrupt it (bad bind, unknown keys, bad cron).
# Gateway recreates it with defaults. Critical settings come from env vars.
CONFIG="$STATE/openclaw.json"
if [ -f "$CONFIG" ]; then
    cp "$CONFIG" "${CONFIG}.bak" 2>/dev/null || true
    rm -f "$CONFIG"
    echo "Cleared openclaw.json (backed up to .bak)"
fi

# Start gateway
node openclaw.mjs gateway --allow-unconfigured --bind lan --port 18789 &
GATEWAY_PID=$!
echo "Gateway PID: $GATEWAY_PID"

# Auto-approve device pairing loop
(
    sleep 10
    echo "=== Auto-approve ==="
    node openclaw.mjs devices approve --latest 2>&1 || true

    while kill -0 $GATEWAY_PID 2>/dev/null; do
        sleep 15
        echo "=== Auto-approve ==="
        node openclaw.mjs devices approve --latest 2>&1 || true
    done
) &

wait $GATEWAY_PID
