# Agent Context & Configuration History

> **Pre budúce Claude Code sessiony:** Prečítaj tento súbor + `RAILWAY_DEPLOY.md` + `AGENTS.md` skôr ako robíš čokoľvek s Railway alebo agentmi.
> **Pre Juraja:** Tu nájdeš prehľad všetkého čo bolo nastavené, prečo a ako to funguje.

---

## Čo je toto za repo

Toto je **osobný fork** `openclaw/openclaw` — open-source AI gateway/agent frameworku.
Fork: `https://github.com/vrontoparsan/OpenClaw`
Docker image (auto-build z main): `ghcr.io/vrontoparsan/openclaw:latest`

**Zmeny oproti originálu:**
- `Dockerfile` — `USER root` na konci (Railway volume permissions fix)
- `start.sh` — kompletne prepísaný (pozri nižšie)
- `RAILWAY_DEPLOY.md` — deployment guide
- `AGENT_CONTEXT.md` — tento súbor
- `new-agent.sh` — script na vytvorenie nového Railway projektu per agent

---

## Architektúra

```
[Juraj / zákazník]
      │ HTTPS
      ▼
[Railway: openclaw-<name>]   ← každý zákazník = vlastný Railway projekt
      │
      ├── Docker: ghcr.io/vrontoparsan/openclaw:latest
      ├── Volume: /data  (perzistentné)
      │     ├── /data/.openclaw/     ← OPENCLAW_STATE_DIR
      │     │     ├── devices/paired.json   (Record<string,PairedDevice> = object {})
      │     │     ├── credentials/telegram-default-allowFrom.json
      │     │     └── openclaw.json.bak     (backup pred resetom)
      │     └── /data/workspace/     ← OPENCLAW_WORKSPACE_DIR
      │
      └── start.sh spúšťa gateway ako root na porte 18789

[Railway: token-refresher]   ← samostatný projekt, obnovuje OAuth token
      └── každých ~7.5h refreshuje ANTHROPIC_OAUTH_TOKEN pre všetkých agentov
```

---

## Bežiace agenty

| Meno | URL | Gateway token | Railway projekt |
|------|-----|---------------|-----------------|
| **main** (Mr. Data / Juraj) | https://openclaw-production-acbc.up.railway.app | `superagency-openclaw-2026-juraj` | `c8a7348f-1001-450d-a4d1-a8a2ebd4872e` |
| **manzelka** | https://openclaw-production-b97f.up.railway.app | `openclaw-manzelka-1771776441` | `e3a21f70-fbf4-44ea-800c-0c2686b69910` |
| **wecko** | https://openclaw-production-8894.up.railway.app | `openclaw-wecko-1771778534` | `8c021172-3177-4cbc-8b36-bfdb9c3c2f8e` |
| **klient2** | https://openclaw-production-deb6.up.railway.app | `openclaw-klient2-1771778534` | `a7d40d70-0be0-47f5-bd8b-51097a757436` |

**Dashboard URL formát:** `https://<domain>/#token=<gateway-token>`
**Chat URL formát:** `https://<domain>/chat?session=main#token=<gateway-token>`

---

## start.sh — čo robí a prečo

```
1. mkdir -p /data/.openclaw/devices /data/.openclaw/credentials
2. Zapíše devices/paired.json ako {} (OBJECT, nie array! — kritické)
3. Zapíše telegram-default-allowFrom.json z TELEGRAM_ALLOW_FROM env var
4. Zmaže /data/.openclaw/openclaw.json (agent ho môže pokaziť — viz história nižšie)
5. Spustí gateway: node openclaw.mjs gateway --allow-unconfigured --bind lan --port 18789
6. Auto-approve loop každých 15s
```

**Prečo root:** Railway volume `/data` je vlastnený rootom, node user (uid 1000) doň nemôže písať.

**Prečo mazať openclaw.json:** Agent (Mr. Data) do neho zapisoval:
- `gateway.bind = "loopback"` → gateway nedostupný z internetu (502)
- `plugins.entries.telegram.streaming` → neznámy kľúč, gateway crash
- `cron` config s neplatnými job entries → TypeError na štarte
Riešenie: zmazať pri každom štarte, gateway vytvorí čistý default. Backup zostane ako `.bak`.

---

## Token Refresher

**Repo:** `vrontoparsan/token-refresher` (private)
**Railway projekt:** `36eb106b-c345-4b93-9431-98c3aa24acef`

**Ako funguje:**
- Číta `TOKEN_EXPIRES_AT` env var pri štarte
- Ak token platí → len naplánuje refresh 30 min pred expiráciou, **nič neaktualizuje**
- Ak token expiroval → refreshuje okamžite
- Po refreshi: uloží nový `ANTHROPIC_REFRESH_TOKEN` + `TOKEN_EXPIRES_AT` do vlastných env vars

**Prečo nie okamžitý refresh pri štarte:** `variableUpsert` na Railway triggeruje redeploy. Ak refresher crashuje a reštartuje, spôsobí redeployment loop na všetkých agentoch.

**OAuth endpoint:** `https://platform.claude.com/v1/oauth/token`
**Client ID:** `9d1c250a-e61b-44d9-88ed-5944d1962f5e`
**User-Agent required:** `claude-code/2.1.50 (linux)` (bez toho vráti 403)
**Expiry:** 28800s = 8 hodín

**Nový token kedykoľvek:** `cat ~/.claude/.credentials.json` → `claudeAiOauth.accessToken`

---

## Mr. Data — záloha a obnova

Agent si sám vytvoril zálohovací systém:
- **Repo:** `https://github.com/vrontoparsan/mr-data-backup` (private)
- **Heslo na dešifrovanie:** `MrData2026Juraj`
- **Inštrukcie:** `RECOVERY.md` v tom repo

Obsahuje: Railway token, GitHub tokeny, GoDaddy, Websupport, Google OAuth, LifeOS, DevOS, Nove API kľúče — všetko zašifrované cez `openssl enc -aes-256-cbc`.

---

## Claude Code vo vnútri agenta

Claude Code má `~/.claude/` na ephemeral overlay → zmizne po reštarte.

**Odporúčané riešenie (trvalé):**
```bash
mv ~/.claude /data/.claude && ln -s /data/.claude ~/.claude
```

**Alternatíva (per-príkaz):**
```bash
ANTHROPIC_API_KEY=$ANTHROPIC_OAUTH_TOKEN claude ...
```

---

## Railway API — kľúčové poznatky

```
Token: 774d3dd9-4d9d-4308-8840-ecb4dc8964cd
Workspace (personal): 62a224e4-658b-4299-9989-89d6c0e5c456  ← povinný pre projectCreate
URL: https://backboard.railway.app/graphql/v2
```

**Dôležité:**
- `query { projects }` → vracia prázdne. Použi: `query { me { workspaces { projects { ... } } } }`
- `variableCollectionUpsert` prepíše VŠETKY env vars — pre update jednej použi `variableUpsert`
- `serviceInstanceUpdate` s `startCommand` sa **ignoruje** — Railway používa Docker CMD
- Zmena env var cez `variableUpsert` automaticky triggeruje redeploy

---

## História kritických bugov a opráv

| Dátum | Bug | Oprava |
|-------|-----|--------|
| 2026-02-21 | `paired.json` zapísaný ako `[]` (array) — devices approve nefungovalo | Zmenené na `{}` v start.sh |
| 2026-02-21 | `exec su node` zahadzoval env vars | Odstránený su, gateway beží ako root |
| 2026-02-22 | EACCES: /data/ owned by root | Dockerfile `USER root`, start.sh fixuje permissions |
| 2026-02-22 | `openclaw.json: streaming` unknown key → crash | start.sh maže celý openclaw.json pri štarte |
| 2026-02-22 | `gateway.bind=loopback` → 502 | start.sh maže openclaw.json |
| 2026-02-22 | cron TypeError → gateway crash | start.sh maže openclaw.json |
| 2026-02-23 | token-refresher triggeroval redeploy loop | Pridaný `TOKEN_EXPIRES_AT` check na štarte |

---

## Čo treba urobiť pri ďalšej session

- [ ] Agent (Mr. Data) má presunúť `~/.claude` na `/data/.claude` (symlink)
- [ ] Telegram pre manzelku, wecko, klient2 (zatiaľ bez Telegramu)
- [ ] Riešiť bezpečnosť prístupu (zatiaľ len token v URL)
- [ ] Pridať nových agentov: `bash new-agent.sh --name "X"` + vygenerovať doménu

---

*Posledná aktualizácia: 2026-02-23*
