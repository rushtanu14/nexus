<div align="center">

<br/>

```
  ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗
  ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝
  ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗
  ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║
  ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║
  ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
```

### *the agent harness that turns any local model into an autonomous personal assistant*

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

> **100% local, zero cloud** 

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

**1 — install deps**

```bash
npm install
```

**2 — launch**

```bash
./run.sh
```

> builds the native app bundle and opens it. that's it.

---

## ◈ engine

the engine starts automatically inside the app. for standalone engine development:

```bash
npm start
```

confirm it's alive:

```
GET http://127.0.0.1:3131/health
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

## ◈ local ai

nexus runs on **ollama** by default — fully offline, no keys, no calls home.

```bash
npm run model:serve    # start ollama
npm run model:pull     # pull default models
```

`model:pull` fetches:

```
qwen2.5-coder:1.5b   →  lightweight planner
nomic-embed-text     →  semantic embeddings
```

the engine default is `qwen2.5-coder:7b`. pull it for full power:

```bash
ollama pull qwen2.5-coder:7b
```

running on a lighter machine? dial it back:

```bash
OLLAMA_MODEL=qwen2.5-coder:1.5b npm start
```

> switch between **ollama**, **lm studio**, and **openai-compatible** providers live inside the app via the nex brain view — no restart needed.

---

## ◈ memory

semantic memory is opt-in. when enabled, nexus stores and retrieves local workflow context via **qdrant** — a self-hosted vector db.

```bash
npm run memory:pull     # pull qdrant image
npm run memory:start    # spin it up
```

dashboard lives at:

```
http://127.0.0.1:6333/dashboard
```

storage path: `./qdrant_storage`

```bash
npm run memory:stop     # shut it down
```

---

## ◈ development

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
