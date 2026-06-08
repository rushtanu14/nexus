<div align="center">

<h1 align="center">

```
███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗
████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝
██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗
██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║
██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║
╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
```

</h1>

_**the agent harness that turns any local model into your autonomous personal assistant**_

<br/>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-Native-111111?style=for-the-badge&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/Voice-First-111111?style=for-the-badge&logo=waveform&logoColor=white" />
  <img src="https://img.shields.io/badge/On--Device-Inference-111111?style=for-the-badge&logo=ollama&logoColor=white" />
  <img src="https://img.shields.io/badge/MCP-500%2B-111111?style=for-the-badge&logo=serverless&logoColor=white" />
  <img src="https://img.shields.io/badge/License-MIT-111111?style=for-the-badge&logo=opensourceinitiative&logoColor=white" />
</p>
<br/>

<p align="center">
  <img height="130" src="https://github.com/user-attachments/assets/0faa7179-e48c-43e2-ad4d-d46a86379c49" />
   <img height="130" src="https://github.com/user-attachments/assets/93917c1c-65bd-415e-8ed2-681c5e43e7ee" />
  <img height="130" alt="Screenshot 2026-06-03 at 11 06 59 PM" src="https://github.com/user-attachments/assets/41f5dfaa-95bb-4761-8b4c-52ed53d9298f" />
  <img height="130" alt="E1E95546-61D4-49A0-9591-AD9F5C3CA057" src="https://github.com/user-attachments/assets/da4991fb-f346-48e6-9cf3-0a21f093c365" />

</div>

<br/>

<details>
<summary><b>architecture</b></summary>

<br/>

```text
┌─────────────────────────────────────────────────────────────────────┐
│                         LOCAL DEVICE LAYER                          │
│                                                                     │
│   Browser      Filesystem      Shell      HTTP      MCP Tools        │
│      │              │            │         │           │             │
│      └──────────────┴────────────┴─────────┴───────────┘             │
│                              │                                      │
│                              ▼                                      │
│                    ╭─────────────────────╮                          │
│                    │     NEXUS CORE      │                          │
│                    │  local inference    │                          │
│                    │  intent detection   │                          │
│                    ╰──────────┬──────────╯                          │
│                               │                                     │
│                               ▼                                     │
│        ┌───────────────────────────────────────────────┐            │
│        │              AGENT HARNESS                    │            │
│        │                                               │            │
│        │   planner ── router ── verifier ── memory     │            │
│        └──────┬─────────┬──────────┬──────────┬────────┘            │
│               │         │          │          │                     │
│               ▼         ▼          ▼          ▼                     │
│          Browser     Shell      Files      MCP Agents               │
│          Agent       Agent      Agent      Gmail · Slack · Drive     │
│               │         │          │          │                     │
│               └─────────┴──────────┴──────────┘                     │
│                              │                                      │
│                              ▼                                      │
│                    verified actions on your machine                  │
│                                                                     │
│        Ollama  ·  LM Studio  ·  OpenAI-Compatible  ·  Local AI       │
└─────────────────────────────────────────────────────────────────────┘
```

</details>

</div>


## start

<details>
<summary><b>quick start</b></summary>

<br/>

```bash
docker compose up -d --build && ./run.sh
```

starts Nexus, Ollama, Qdrant, default models, and the native app.

| service | url |
|----------|----------|
| engine | `127.0.0.1:3131` |
| ollama | `127.0.0.1:11434` |
| qdrant | `127.0.0.1:6333/dashboard` |

switch models:

```bash
OLLAMA_MODEL=qwen2.5-coder:7b docker compose up -d
```

</details>

<details>
<summary><b>mcp registration</b></summary>

<br/>

register an MCP:

```bash
curl -X POST http://127.0.0.1:3131/mcp/register \
  -H 'content-type: application/json' \
  -d '{"app":"gmail","url":"http://127.0.0.1:9001"}'
```

start the built-in local provider bridge:

```bash
npm run mcp:bridge
```

then:

```bash
npm run mcp:register
curl http://127.0.0.1:3131/mcp/list
```

| app | bridge port | connect type |
|------|------|------|
| `gmail` | `9001` | Google OAuth |
| `google-workspace` | `9002` | Google OAuth |
| `google-drive` | `9003` | Google OAuth |
| `slack` | `9004` | Slack OAuth (read-only) |
| `notion` | `9005` | Notion OAuth |

</details>

<details>
<summary><b>connectors & oauth</b></summary>

<br/>

Universal connect page:

```text
http://127.0.0.1:9001/connectors
```

The bridge exposes tools before a user connects, but a connector is only marked connected after OAuth completes and a provider test call succeeds.

Credentials are stored under:

```text
.nexus-data/mcp-secrets/
```

Users never paste API keys, OAuth tokens, client IDs, or client secrets.

If a connector is not configured, Nexus displays a setup error instead of requesting secrets.

### Local Redirect URIs

| connector | redirect URI |
|----------|----------|
| Gmail | `http://127.0.0.1:9001/oauth/callback` |
| Google Calendar | `http://127.0.0.1:9002/oauth/callback` |
| Google Drive | `http://127.0.0.1:9003/oauth/callback` |
| Slack | `http://127.0.0.1:9004/oauth/callback` |
| Notion | `http://127.0.0.1:9005/oauth/callback` |

Slack remains read-only.

</details>

<details>
<summary><b>api</b></summary>

<br/>

```text
POST /node/generate
POST /node/save
GET  /node/list

POST /node/run
POST /nex/complete
POST /brain/prepare

GET  /memory/health
```

</details>

<details>
<summary><b>configuration</b></summary>

<br/>

| variable | default |
|----------|----------|
| `PORT` | `3131` |
| `OLLAMA_MODEL` | `qwen2.5-coder:1.5b` |
| `NEXUS_MEMORY_ENABLED` | `1` |
| `NEXUS_QDRANT_URL` | `127.0.0.1:6333` |
| `OLLAMA_BASE_URL` | `127.0.0.1:11434` |

</details>

<details>
<summary><b>development</b></summary>

<br/>

```bash
npm test

cd native-macos
swift run LocalWorkflowStudioNativeModelTests

swift run LocalWorkflowStudioNativeIntegrationTests

./scripts/build-app.sh
```

</details>
