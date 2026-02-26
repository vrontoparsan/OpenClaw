#!/bin/sh
echo "=== Starting OpenClaw Gateway ==="
echo "Running as: $(id)"

STATE="${OPENCLAW_STATE_DIR:-/home/node/.openclaw}"
echo "STATE_DIR: $STATE"

# Create state dirs
mkdir -p "$STATE/devices" "$STATE/credentials"

# Remove stale .lock files from previous runs
find "$STATE" -name "*.lock" -delete 2>/dev/null && echo "Stale locks cleaned" || true

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
    fs.writeFileSync('$CONFIG',JSON.stringify(cfg,null,2));
    console.log('openclaw.json configured (groups=open, mention=required)');
" 2>&1 || true

# Auto-approve device pairing loop (background)
(
    sleep 10
    while true; do
        echo "=== Auto-approve ==="
        node openclaw.mjs devices approve --latest 2>&1 || true
        sleep 15
    done
) &

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
