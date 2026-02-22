# Railway Agent Deployment Guide

This document describes how to spin up a new isolated OpenClaw agent for a customer on Railway.
**Read this file before doing any Railway deployment work.**

---

## Architecture

Each customer gets their own Railway **project** (not just a service) for full isolation:
- Docker image: `ghcr.io/vrontoparsan/openclaw:latest` (auto-built by GitHub Actions on push to `main`)
- Persistent volume mounted at `/data`
- State dir: `/data/.openclaw`, workspace: `/data/workspace`
- Gateway port: `18789`
- Runs as `root` (required so `start.sh` can fix `/data` volume permissions)

---

## Quick Start

```bash
bash new-agent.sh --name "nazov-agenta"
# Optional flags:
bash new-agent.sh --name "nazov" --telegram "BOT_TOKEN" --telegram-allow "123456789" --prompt "Ty si..."
```

Then generate a domain (Railway does not auto-create one):

```python
# See "Generate Domain" section below
```

**Dashboard URL** (send to customer):
```
https://<domain>/#token=<gateway-token>
```

The gateway token is printed by `new-agent.sh` as `Gateway token: openclaw-<name>-<timestamp>`.

---

## Credentials & IDs

### Railway API token
```
774d3dd9-4d9d-4308-8840-ecb4dc8964cd
```

### Railway Workspace ID (vrontoparsan's Projects)
```
62a224e4-658b-4299-9989-89d6c0e5c456
```
Required for `projectCreate` — personal accounts need this, `teamId` is null.

### ANTHROPIC_OAUTH_TOKEN
**OAuth tokens expire!** When they do, agents return HTTP 401 `authentication_error: OAuth token has expired`.

To get a fresh token:
```bash
cat ~/.claude/.credentials.json
# Look for: claudeAiOauth.accessToken  →  sk-ant-oat01-...
```

Update a single Railway env var without overwriting others:
```python
import urllib.request, json

token = '774d3dd9-4d9d-4308-8840-ecb4dc8964cd'
url = 'https://backboard.railway.app/graphql/v2'

payload = {
    'query': '''mutation($input: VariableUpsertInput!) {
        variableUpsert(input: $input)
    }''',
    'variables': {
        'input': {
            'projectId': '<PROJECT_ID>',
            'serviceId': '<SERVICE_ID>',
            'environmentId': '<ENV_ID>',
            'name': 'ANTHROPIC_OAUTH_TOKEN',
            'value': '<NEW_TOKEN>',
        }
    }
}
data = json.dumps(payload).encode()
req = urllib.request.Request(url, data=data, headers={
    'Authorization': f'Bearer {token}', 'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'
})
with urllib.request.urlopen(req) as r:
    print(json.loads(r.read().decode()))
```

**Update all agents at once** by listing projects first:
```python
# query { me { workspaces { id name projects { edges { node { id name services { edges { node { id } } } environments { edges { node { id } } } } } } } } }
```

---

## Existing Agents

| Name | Project ID | Service ID | Environment ID | Domain | Gateway Token |
|------|-----------|------------|----------------|--------|---------------|
| main (OpenClaw) | `c8a7348f-1001-450d-a4d1-a8a2ebd4872e` | `929a8d93-3dcc-4bc6-ab81-05eab26c0ed8` | `971ada44-e739-4697-a714-8fbebc5da183` | `openclaw-production-acbc.up.railway.app` | `superagency-openclaw-2026-juraj` |
| manzelka | `e3a21f70-fbf4-44ea-800c-0c2686b69910` | `52d1f664-fc5b-4015-bf0c-293fadfe086e` | `e5ba819f-dddb-4caf-8aa5-4b78b6e65c49` | `openclaw-production-b97f.up.railway.app` | `openclaw-manzelka-1771776441` |
| wecko | `8c021172-3177-4cbc-8b36-bfdb9c3c2f8e` | `296bc47c-4e0d-4ad2-a4ce-87c1369517a2` | `5340ee9b-bd62-4bfe-8ff1-c3d5fb1de368` | `openclaw-production-8894.up.railway.app` | `openclaw-wecko-1771778534` |
| klient2 | `a7d40d70-0be0-47f5-bd8b-51097a757436` | `3d6eb538-d616-4434-bbc2-c55605a341f4` | `5218d206-22c7-498a-af35-73c8bbc726b8` | `openclaw-production-deb6.up.railway.app` | `openclaw-klient2-1771778534` |

---

## Generate Domain (after new-agent.sh)

`new-agent.sh` does NOT auto-generate a domain. Run this after:

```python
import urllib.request, json

token = '774d3dd9-4d9d-4308-8840-ecb4dc8964cd'
url = 'https://backboard.railway.app/graphql/v2'

query = '''mutation {
  serviceDomainCreate(input: {
    serviceId: "<SERVICE_ID>"
    environmentId: "<ENV_ID>"
  }) { domain }
}'''

payload = json.dumps({'query': query}).encode()
req = urllib.request.Request(url, data=payload, headers={
    'Authorization': f'Bearer {token}', 'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'
})
with urllib.request.urlopen(req) as r:
    result = json.loads(r.read().decode())
    print("https://" + result['data']['serviceDomainCreate']['domain'])
```

---

## Environment Variables Set Per Agent

| Variable | Value |
|----------|-------|
| `OPENCLAW_GATEWAY_TOKEN` | `openclaw-<name>-<timestamp>` |
| `ANTHROPIC_OAUTH_TOKEN` | from `~/.claude/.credentials.json` |
| `OPENCLAW_STATE_DIR` | `/data/.openclaw` |
| `OPENCLAW_WORKSPACE_DIR` | `/data/workspace` |
| `PORT` | `18789` |
| `NODE_ENV` | `production` |
| `TELEGRAM_BOT_TOKEN` | (optional) |
| `TELEGRAM_ALLOW_FROM` | (optional, comma-separated Telegram user IDs) |
| `OPENCLAW_SYSTEM_PROMPT` | (optional) |

---

## Key Files

- `new-agent.sh` — creates a new Railway project end-to-end
- `Dockerfile` — runs as `root`; builds image pushed to `ghcr.io/vrontoparsan/openclaw:latest`
- `start.sh` — fixes `/data` permissions, writes `paired.json` as `{}` (object, not array!), writes `telegram-default-allowFrom.json`, starts gateway

### Critical: paired.json format
OpenClaw expects `Record<string, PairedDevice>` — an **object** `{}`, NOT an array `[]`.
`start.sh` preserves existing entries and writes `{}` if missing. Never write `[]`.

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `HTTP 401 OAuth token has expired` | `ANTHROPIC_OAUTH_TOKEN` expired | Get new token from `~/.claude/.credentials.json`, update via `variableUpsert` |
| `1008: gateway token missing` | Missing token in URL | Use `https://<domain>/#token=<gateway-token>` |
| `EACCES: permission denied /data` | Volume owned by root, node can't write | Already fixed: Dockerfile uses `USER root`, start.sh chowns /data |
| `pairing required` loop | `paired.json` was `[]` not `{}` | Already fixed in start.sh |
| `projectCreate: workspaceId required` | Personal account needs workspace | Use workspace ID `62a224e4-658b-4299-9989-89d6c0e5c456` |
