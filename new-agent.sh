#!/bin/bash
# new-agent.sh - Spusti nového OpenClaw agenta na Railway
# Použitie: ./new-agent.sh --name "manzelka" --telegram "BOT_TOKEN" --prompt "Ty si..."

set -e

# --- Konfigurácia ---
RAILWAY_TOKEN="774d3dd9-4d9d-4308-8840-ecb4dc8964cd"
RAILWAY_PROJECT_ID="c8a7348f-1001-450d-a4d1-a8a2ebd4872e"
RAILWAY_ENVIRONMENT_ID="971ada44-e739-4697-a714-8fbebc5da183"
DOCKER_IMAGE="ghcr.io/vrontoparsan/openclaw:latest"
ANTHROPIC_OAUTH_TOKEN="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"

# --- Parametre ---
NAME=""
TELEGRAM_TOKEN=""
SYSTEM_PROMPT=""
PORT=18789

while [[ $# -gt 0 ]]; do
  case $1 in
    --name) NAME="$2"; shift 2 ;;
    --telegram) TELEGRAM_TOKEN="$2"; shift 2 ;;
    --prompt) SYSTEM_PROMPT="$2"; shift 2 ;;
    *) echo "Neznámy parameter: $1"; exit 1 ;;
  esac
done

if [[ -z "$NAME" ]]; then
  echo "Chýba --name"
  exit 1
fi

GATEWAY_TOKEN="openclaw-${NAME}-$(date +%s)"

echo "🚀 Vytváram agenta: $NAME"
echo "   Gateway token: $GATEWAY_TOKEN"

# --- GraphQL helper ---
gql() {
  python3 -c "
import urllib.request, json, sys
payload = json.dumps({'query': sys.stdin.read()}).encode()
req = urllib.request.Request(
  'https://backboard.railway.app/graphql/v2',
  data=payload,
  headers={'Authorization': 'Bearer $RAILWAY_TOKEN', 'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'}
)
with urllib.request.urlopen(req) as r:
  print(r.read().decode())
"
}

# 1. Vytvor Railway service
echo "📦 Vytváram Railway service..."
SERVICE_RESULT=$(echo "mutation {
  serviceCreate(input: {
    projectId: \"$RAILWAY_PROJECT_ID\"
    name: \"openclaw-$NAME\"
  }) { id name }
}" | gql)

SERVICE_ID=$(echo "$SERVICE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['serviceCreate']['id'])")
echo "   Service ID: $SERVICE_ID"

# 2. Nastav Docker image
echo "🐳 Nastavujem Docker image..."
echo "mutation {
  serviceInstanceUpdate(
    serviceId: \"$SERVICE_ID\",
    environmentId: \"$RAILWAY_ENVIRONMENT_ID\",
    input: {
      source: { image: \"$DOCKER_IMAGE\" }
      healthcheckPath: \"/health\"
      healthcheckTimeout: 60
      restartPolicyType: ON_FAILURE
      restartPolicyMaxRetries: 3
    }
  )
}" | gql > /dev/null

# 3. Nastav env vars
echo "⚙️  Nastavujem env vars..."

DEVICE_APPROVE_CMD="node -e \"const fs=require('fs');const d='/data/.openclaw/devices';fs.mkdirSync(d,{recursive:true});const f=d+'/paired.json';let arr=[];try{arr=JSON.parse(fs.readFileSync(f,'utf8'))||[];}catch(e){}console.log('Paired devices:',arr.length);fs.writeFileSync(f,JSON.stringify(arr));\" && node openclaw.mjs gateway --allow-unconfigured --bind lan --port $PORT"

python3 << PYEOF
import urllib.request, json

token = '$RAILWAY_TOKEN'
url = 'https://backboard.railway.app/graphql/v2'

vars = {
    'OPENCLAW_GATEWAY_TOKEN': '$GATEWAY_TOKEN',
    'ANTHROPIC_OAUTH_TOKEN': '$ANTHROPIC_OAUTH_TOKEN',
    'OPENCLAW_STATE_DIR': '/data/.openclaw',
    'OPENCLAW_WORKSPACE_DIR': '/data/workspace',
    'PORT': '$PORT',
    'NODE_ENV': 'production',
}

if '$TELEGRAM_TOKEN':
    vars['TELEGRAM_BOT_TOKEN'] = '$TELEGRAM_TOKEN'

if '$SYSTEM_PROMPT':
    vars['OPENCLAW_SYSTEM_PROMPT'] = '$SYSTEM_PROMPT'

payload = {
    'query': '''mutation(\$input: VariableCollectionUpsertInput!) {
        variableCollectionUpsert(input: \$input)
    }''',
    'variables': {
        'input': {
            'projectId': '$RAILWAY_PROJECT_ID',
            'serviceId': '$SERVICE_ID',
            'environmentId': '$RAILWAY_ENVIRONMENT_ID',
            'variables': vars
        }
    }
}

data = json.dumps(payload).encode()
req = urllib.request.Request(url, data=data, headers={
    'Authorization': f'Bearer {token}',
    'Content-Type': 'application/json',
    'User-Agent': 'Mozilla/5.0'
})
with urllib.request.urlopen(req) as resp:
    print(resp.read().decode())
PYEOF

# 4. Vytvor volume
echo "💾 Vytváram volume..."
VOLUME_RESULT=$(echo "mutation {
  volumeCreate(input: {
    projectId: \"$RAILWAY_PROJECT_ID\"
    environmentId: \"$RAILWAY_ENVIRONMENT_ID\"
    serviceId: \"$SERVICE_ID\"
    mountPath: \"/data\"
  }) { id name }
}" | gql)
echo "   Volume: $(echo $VOLUME_RESULT | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('volumeCreate',{}).get('name','?'))")"

# 5. Deploy
echo "🚀 Spúšťam deployment..."
echo "mutation {
  serviceInstanceDeploy(
    serviceId: \"$SERVICE_ID\",
    environmentId: \"$RAILWAY_ENVIRONMENT_ID\"
  )
}" | gql > /dev/null

echo ""
echo "✅ Agent '$NAME' vytvorený!"
echo "   Gateway token: $GATEWAY_TOKEN"
echo "   Service ID: $SERVICE_ID"
echo "   Deployment beží, počkaj ~2 minúty..."
echo ""
echo "   URL bude: https://openclaw-${NAME}-production.up.railway.app"
