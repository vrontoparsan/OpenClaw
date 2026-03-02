#!/bin/sh
echo "=== Starting OpenClaw Gateway ==="
echo "Running as: $(id)"

STATE="${OPENCLAW_STATE_DIR:-/home/node/.openclaw}"
echo "STATE_DIR: $STATE"

# Create state dirs
mkdir -p "$STATE/devices" "$STATE/credentials"

# Remove stale .lock files from previous runs
find "$STATE" -name "*.lock" -delete 2>/dev/null && echo "Stale locks cleaned" || true

# Reset device pairing state on every startup (fresh pairing via --allow-unconfigured)
rm -rf "$STATE/devices" "$STATE/identity"
mkdir -p "$STATE/devices"
echo '{}' > "$STATE/devices/paired.json"
echo "Device state reset (clean pairing)"

# Write telegram allowFrom from env var
if [ -n "\$TELEGRAM_ALLOW_FROM" ]; then
    node -e "
        const ids = process.env.TELEGRAM_ALLOW_FROM.split(',').map(id => id.trim());
        const data = JSON.stringify({version:1,allowFrom:ids},null,2)+'\n';
        require('fs').writeFileSync('$STATE/credentials/telegram-default-allowFrom.json', data);
        console.log('Telegram allowFrom:', ids);
    " 2>&1 || true
fi

# Fix openclaw.json — keep valid settings, fix agent-corrupted ones.
CONFIG="$STATE/openclaw.json"
node -e "
    const fs=require('fs');
    let cfg={};
    try{cfg=JSON.parse(fs.readFileSync('$CONFIG','utf8'));}catch(e){}
    // Fix agent-corrupted fields
    if(cfg.gateway){
        if(cfg.gateway.bind&&cfg.gateway.bind!=='lan')cfg.gateway.bind='lan';
    }
    // Remove known bad keys
    const tel=cfg?.plugins?.entries?.telegram;
    if(tel&&tel.streaming!==undefined)delete tel.streaming;
    // Enable Telegram groups (open policy + require @mention)
    if(!cfg.channels)cfg.channels={};
    if(!cfg.channels.telegram)cfg.channels.telegram={};
    cfg.channels.telegram.groupPolicy='open';
    if(!cfg.channels.telegram.groups)cfg.channels.telegram.groups={};
    if(!cfg.channels.telegram.groups['*'])cfg.channels.telegram.groups['*']={};
    cfg.channels.telegram.groups['*'].requireMention=true;
    // Disable device auth for Control UI — token-only auth via OPENCLAW_GATEWAY_TOKEN
    if(!cfg.gateway)cfg.gateway={};
    if(!cfg.gateway.controlUi)cfg.gateway.controlUi={};
    cfg.gateway.controlUi.dangerouslyDisableDeviceAuth=true;
    // Set allowed origins for non-loopback Control UI (required in v2026.2.26+)
    const domain=process.env.RAILWAY_PUBLIC_DOMAIN||process.env.RAILWAY_STATIC_URL;
    if(domain){cfg.gateway.controlUi.allowedOrigins=['https://'+domain];}
    else{cfg.gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback=true;}
    // Remove any persisted gateway auth token so OPENCLAW_GATEWAY_TOKEN env var takes effect
    if(cfg.gateway.auth&&cfg.gateway.auth.token)delete cfg.gateway.auth.token;
    if(cfg.gateway.auth&&cfg.gateway.auth.mode)delete cfg.gateway.auth.mode;
    fs.writeFileSync('$CONFIG',JSON.stringify(cfg,null,2));
    console.log('openclaw.json configured (groups=open, mention=required, deviceAuth=disabled)');
" 2>&1 || true

# Start gateway in restart loop (survives SIGUSR1 internal restarts)
while true; do
    echo "=== Gateway starting ==="
    node openclaw.mjs gateway --allow-unconfigured --bind lan --port 18789
    EXIT_CODE=$?
    echo "Gateway exited (code $EXIT_CODE), restarting in 3s..."
    # Clean stale locks before restart
    find "$STATE" -name "*.lock" -delete 2>/dev/null || true
    sleep 3
done
