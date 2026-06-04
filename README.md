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

> **the agent harness that turns any local model into your autonomous personal assistant**

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
  <img height="300" src="https://github.com/user-attachments/assets/0faa7179-e48c-43e2-ad4d-d46a86379c49" />
   <img height="300" src="https://github.com/user-attachments/assets/93917c1c-65bd-415e-8ed2-681c5e43e7ee" />
</p>

<br/>

<p align="center">
  <img height="300" alt="Screenshot 2026-06-03 at 11 06 59 PM" src="https://github.com/user-attachments/assets/41f5dfaa-95bb-4761-8b4c-52ed53d9298f" />
  <img height="300" alt="E1E95546-61D4-49A0-9591-AD9F5C3CA057" src="https://github.com/user-attachments/assets/da4991fb-f346-48e6-9cf3-0a21f093c365" />



<br/>

```text
┌─────────────────────────────────────────────────────────────────────┐
│                         LOCAL DEVICE LAYER                          │
│                                                                     │
│   BROWSER        FILESYSTEM        SHELL        HTTP        MCP     │
│      │               │              │           │          │        │
│      └───────────────┴──────────────┴───────────┴──────────┘        │
│                              │                                      │
│                              ▼                                      │
│                    ╭─────────────────────╮                          │
│                    │     NEXUS CORE      │                          │
│                    │  always-listening   │                          │
│                    │  local inference    │                          │
│                    ╰──────────┬──────────╯                          │
│                               │                                     │
│                 infers intent │ detects MCP actions                 │
│                               ▼                                     │
│        ┌───────────────────────────────────────────────┐            │
│        │              AGENT HARNESS                    │            │
│        │                                               │            │
│        │   planner ── router ── verifier ── memory     │            │
│        │      │         │          │          │         │           │
│        └──────┼─────────┼──────────┼──────────┼─────────┘           │
│               │         │          │          │                     │
│               ▼         ▼          ▼          ▼                     │
│          subagent   subagent   subagent   subagent                  │
│          browser    shell      files      mcp-tools                 │
│               │         │          │          │                     │
│               └─────────┴──────────┴──────────┘                     │
│                              │                                      │
│                              ▼                                      │
│                    completes actions for you                        │
│                                                                     │
│        OLLAMA  ·  LM STUDIO  ·  OPENAI-COMPATIBLE  ·  LOCAL AI      │
└─────────────────────────────────────────────────────────────────────┘

```

</div>


## start

```bash
docker compose up -d --build && ./run.sh
```

starts Nexus, Ollama, Qdrant, default models, and the native app.

| service | url                        |
| ------- | -------------------------- |
| engine  | `127.0.0.1:3131`           |
| ollama  | `127.0.0.1:11434`          |
| qdrant  | `127.0.0.1:6333/dashboard` |

switch models:

```bash
OLLAMA_MODEL=qwen2.5-coder:1.5b docker compose up -d
```

register an MCP:

```bash
curl -X POST http://127.0.0.1:3131/mcp/register \
  -H 'content-type: application/json' \
  -d '{"app":"gmail","url":"http://127.0.0.1:9001"}'
```

---

## api

```text
POST /node/generate   POST /node/save      GET  /node/list
POST /node/run        POST /nex/complete   POST /brain/prepare
GET  /memory/health
```

---

## configuration

| variable               | default            |
| ---------------------- | ------------------ |
| `PORT`                 | `3131`             |
| `OLLAMA_MODEL`         | `qwen2.5-coder:7b` |
| `NEXUS_MEMORY_ENABLED` | `1`                |
| `NEXUS_QDRANT_URL`     | `127.0.0.1:6333`   |
| `OLLAMA_BASE_URL`      | `127.0.0.1:11434`  |

---

<details>
<summary>development</summary>

<br/>

```bash
npm test

cd native-macos
swift run LocalWorkflowStudioNativeModelTests

swift run LocalWorkflowStudioNativeIntegrationTests

./scripts/build-app.sh
```

</details>
