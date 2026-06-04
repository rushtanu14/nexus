<div align="center">
  
<table>
<tr>
<td valign="middle">

<pre>
███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗         
████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝         
██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗         
██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║
██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║
╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
</pre>

</td>
<td valign="middle">

<pre>
the agent harness that
turns any local model
into your autonomous personal assistant
</pre>

</td>
</tr>
</table>

<br/>

![latency](https://img.shields.io/badge/latency-70ms-white?style=flat-square&labelColor=0a0a0a)
![MCPs](https://img.shields.io/badge/MCPs-500+-white?style=flat-square&labelColor=0a0a0a)
![macOS](https://img.shields.io/badge/macOS-14+-white?style=flat-square&labelColor=0a0a0a)

<br/>

<p align="center">
  <img height="120" src="https://github.com/user-attachments/assets/93917c1c-65bd-415e-8ed2-681c5e43e7ee" />
  <img height="120" src="https://github.com/user-attachments/assets/0faa7179-e48c-43e2-ad4d-d46a86379c49" />
  <img height="120" src="https://github.com/user-attachments/assets/b9fd521b-35d3-4827-99c0-bfa3358fc044" />
  <img height="120" src="https://github.com/user-attachments/assets/9ef93fdd-6f96-43b2-af54-99014ca28caa" />
</p>

<br/>

</div>

---

<div align="center">

```
┌─────────────────────────────────────────────────────────────────┐
│  BROWSER  ·  FILESYSTEM  ·  SHELL  ·  HTTP  ·  MCP  ·  AI       │
│                     ↓  workflow primitives  ↓                   │
│                     [ NEXUS AGENT HARNESS ]                     │
│                      ↓  local inference  ↓                      │
│         OLLAMA  ·  LM STUDIO  ·  OPENAI-COMPAT                  │
└─────────────────────────────────────────────────────────────────┘
```

</div>

---

## ◈ quickstart

**start Nexus**

```bash
docker compose up -d --build && ./run.sh
```

this starts the Nexus engine API, Ollama, the default chat model, the embedding model, Qdrant memory, then opens the macOS app.

just start the backend stack:

```bash
docker compose up -d --build
```

the app connects to the Docker stack on localhost. confirm the stack is alive:

```
GET http://127.0.0.1:3131/health
```

stop everything:

```bash
docker compose down
```

---

## ◈ docker stack

`docker compose up -d --build` handles the local services that used to be started one by one:

| service | local URL | purpose |
|---|---|---|
| `engine` | `http://127.0.0.1:3131` | Nexus API, Echo actions, MCP registry, assistant completion |
| `ollama` | `http://127.0.0.1:11434` | local model runtime |
| `ollama-models` | — | pulls `qwen2.5-coder:7b` and `nomic-embed-text` once |
| `qdrant` | `http://127.0.0.1:6333/dashboard` | semantic memory |

stored data lives in Docker volumes: `nexus_engine_data`, `ollama_models`, and `qdrant_storage`.

use a different model without editing files:

```bash
OLLAMA_MODEL=qwen2.5-coder:1.5b docker compose up -d --build
```

real Gmail, Notion, Drive, and other MCP calls still require their MCP server/auth connection. Once the stack is running, register an authenticated MCP endpoint from the app or through:

```bash
curl -X POST http://127.0.0.1:3131/mcp/register \
  -H 'content-type: application/json' \
  -d '{"app":"gmail","url":"http://127.0.0.1:9001"}'
```

### api surface

```
POST  /node/generate      →  generate a workflow node
POST  /node/save          →  persist a node
GET   /node/list          →  list saved nodes
POST  /node/run           →  execute a node
POST  /nex/complete       →  agent completion
POST  /brain/prepare      →  prepare model context
GET   /memory/health      →  vector memory status
```

---

## ◈ development

backend stack:

```bash
npm run docker:start
npm run docker:logs
npm run docker:stop
```

**node runtime tests**
```bash
npm test
```

**native model tests**
```bash
cd native-macos
swift run LocalWorkflowStudioNativeModelTests
```

**native integration tests**
```bash
cd native-macos
swift run LocalWorkflowStudioNativeIntegrationTests
```

**build app bundle**
```bash
cd native-macos
./scripts/build-app.sh
```

---

## ◈ environment

most contributors never need to touch these. they're here when you do.

| variable | default | description |
|---|---|---|
| `PORT` | `3131` | engine port |
| `OLLAMA_MODEL` | `qwen2.5-coder:7b` | planner model |
| `OLLAMA_BASE_URL` | `http://127.0.0.1:11434` | ollama endpoint |
| `NEXUS_ENGINE_ROOT` | — | override engine path |
| `NEXUS_NODE_STORE` | — | override sqlite path |
| `NEXUS_MEMORY_ENABLED` | `1` | set to `0` to disable qdrant |
| `NEXUS_QDRANT_URL` | `http://127.0.0.1:6333` | qdrant endpoint |

---

<div align="center">

![MIT License](https://img.shields.io/badge/license-MIT-white?style=flat-square&labelColor=0a0a0a)

</div>
