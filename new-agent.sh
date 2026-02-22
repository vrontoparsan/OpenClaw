#!/bin/bash
# new-agent.sh - Vytvorí nového OpenClaw agenta vo vlastnom Railway projekte
# Použitie: ./new-agent.sh --name "manzelka" --telegram "BOT_TOKEN" --telegram-allow "123456789" --prompt "Ty si..."

set -e

# --- Konfigurácia ---
RAILWAY_TOKEN="774d3dd9-4d9d-4308-8840-ecb4dc8964cd"
DOCKER_IMAGE="ghcr.io/vrontoparsan/openclaw:latest"
ANTHROPIC_OAUTH_TOKEN="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"

# --- Parametre ---
NAME=""
TELEGRAM_TOKEN=""
TELEGRAM_ALLOW=""   # Telegram user ID (napr. "123456789")
SYSTEM_PROMPT=""
PORT=18789

while [[ $# -gt 0 ]]; do
  case $1 in
    --name)           NAME="$2"; shift 2 ;;
    --telegram)       TELEGRAM_TOKEN="$2"; shift 2 ;;
    --telegram-allow) TELEGRAM_ALLOW="$2"; shift 2 ;;
    --prompt)         SYSTEM_PROMPT="$2"; shift 2 ;;
    *) echo "Neznámy parameter: $1"; exit 1 ;;
  esac
done

if [[ -z "$NAME" ]]; then
  echo "Chýba --name"
  echo "Použitie: $0 --name \"manzelka\" --telegram \"TOKEN\" --telegram-allow \"123456\" --prompt \"Ty si...\""
  exit 1
fi

GATEWAY_TOKEN="openclaw-${NAME}-$(date +%s)"
PROJECT_NAME="openclaw-${NAME}"

echo "🚀 Vytváram agenta: $NAME"
echo "   Projekt:       $PROJECT_NAME"
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

gql_vars() {
  python3 -c "
import urllib.request, json, sys
query, variables = sys.stdin.read().split('|||', 1)
payload = json.dumps({'query': query, 'variables': json.loads(variables)}).encode()
req = urllib.request.Request(
  'https://backboard.railway.app/graphql/v2',
  data=payload,
  headers={'Authorization': 'Bearer $RAILWAY_TOKEN', 'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'}
)
with urllib.request.urlopen(req) as r:
  print(r.read().decode())
"
}

# 1. Vytvor nový Railway projekt
echo ""
echo "📁 Vytváram Railway projekt '$PROJECT_NAME'..."
PROJECT_RESULT=$(echo "mutation {
  projectCreate(input: {
    name: \"$PROJECT_NAME\"
  }) { id name environments { edges { node { id name } } } }
}" | gql)

PROJECT_ID=$(echo "$PROJECT_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['projectCreate']['id'])")
ENVIRONMENT_ID=$(echo "$PROJECT_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data']['projectCreate']['environments']['edges'][0]['node']['id'])")

echo "   Project ID:     $PROJECT_ID"
echo "   Environment ID: $ENVIRONMENT_ID"

# 2. Vytvor service
echo ""
echo "📦 Vytváram service..."
SERVICE_RESULT=$(echo "mutation {
  serviceCreate(input: {
    projectId: \"$PROJECT_ID\"
    name: \"openclaw\"
  }) { id name }
}" | gql)

SERVICE_ID=$(echo "$SERVICE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['serviceCreate']['id'])")
echo "   Service ID: $SERVICE_ID"

# 3. Nastav Docker image + healthcheck
echo ""
echo "🐳 Nastavujem Docker image..."
echo "mutation {
  serviceInstanceUpdate(
    serviceId: \"$SERVICE_ID\",
    environmentId: \"$ENVIRONMENT_ID\",
    input: {
      source: { image: \"$DOCKER_IMAGE\" }
      healthcheckPath: \"/health\"
      healthcheckTimeout: 60
      restartPolicyType: ON_FAILURE
      restartPolicyMaxRetries: 3
    }
  )
}" | gql > /dev/null

# 4. Nastav env vars
echo ""
echo "⚙️  Nastavujem env vars..."

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

if '$TELEGRAM_ALLOW':
    vars['TELEGRAM_ALLOW_FROM'] = '$TELEGRAM_ALLOW'

if '$SYSTEM_PROMPT':
    vars['OPENCLAW_SYSTEM_PROMPT'] = '$SYSTEM_PROMPT'

payload = {
    'query': '''mutation(\$input: VariableCollectionUpsertInput!) {
        variableCollectionUpsert(input: \$input)
    }''',
    'variables': {
        'input': {
            'projectId': '$PROJECT_ID',
            'serviceId': '$SERVICE_ID',
            'environmentId': '$ENVIRONMENT_ID',
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
    result = json.loads(resp.read().decode())
    if result.get('data', {}).get('variableCollectionUpsert'):
        print("   ✓ Env vars nastavené")
    else:
        print("   ⚠️  Chyba:", result)
PYEOF

# 5. Vytvor volume (mountPath /data)
echo ""
echo "💾 Vytváram volume..."
VOLUME_RESULT=$(echo "mutation {
  volumeCreate(input: {
    projectId: \"$PROJECT_ID\"
    environmentId: \"$ENVIRONMENT_ID\"
    serviceId: \"$SERVICE_ID\"
    mountPath: \"/data\"
  }) { id name }
}" | gql)
VOLUME_NAME=$(echo "$VOLUME_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('volumeCreate',{}).get('name','?'))")
echo "   Volume: $VOLUME_NAME"

# 6. Deploy
echo ""
echo "🚀 Spúšťam deployment..."
echo "mutation {
  serviceInstanceDeploy(
    serviceId: \"$SERVICE_ID\",
    environmentId: \"$ENVIRONMENT_ID\"
  )
}" | gql > /dev/null

echo ""
echo "✅ Agent '$NAME' vytvorený!"
echo ""
echo "   Railway projekt: $PROJECT_NAME"
echo "   Project ID:      $PROJECT_ID"
echo "   Service ID:      $SERVICE_ID"
echo "   Gateway token:   $GATEWAY_TOKEN"
echo ""
echo "   ⏳ Deployment beží, počkaj ~3 minúty..."
echo ""
echo "   URL bude: https://openclaw-production.up.railway.app"
echo "   (presné URL nájdeš v Railway dashboarde → projekt $PROJECT_NAME → Settings → Domains)"
echo ""
if [[ -n "$TELEGRAM_TOKEN" ]]; then
  echo "   Telegram: nakonfigurovaný ✓"
  if [[ -n "$TELEGRAM_ALLOW" ]]; then
    echo "   Telegram allow: $TELEGRAM_ALLOW ✓"
  fi
fi
