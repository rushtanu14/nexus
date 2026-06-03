<div align="center">

<img width="276" height="118" alt="Nexus" src="https://github.com/user-attachments/assets/fffb4645-d719-4988-938a-bef235ac5283" />

### local workflows, memory, agents, and automation in a native macOS workspace

<br>

<p align="center">
  <img height="120" src="https://github.com/user-attachments/assets/93917c1c-65bd-415e-8ed2-681c5e43e7ee" />
  <img height="120" src="https://github.com/user-attachments/assets/0faa7179-e48c-43e2-ad4d-d46a86379c49" />
  <img height="120" src="https://github.com/user-attachments/assets/b9fd521b-35d3-4827-99c0-bfa3358fc044" />
  <img height="120" src="https://github.com/user-attachments/assets/9ef93fdd-6f96-43b2-af54-99014ca28caa" />
</p>

</div>

## What Nexus Is

Nexus is a local-first macOS workspace for turning intent into executable workflows. It pairs a SwiftUI native app with a small Node runtime that can generate, save, run, and remember automation nodes across browser actions, files, shell commands, HTTP calls, MCP tools, and local AI.

The goal is simple: a serious personal automation system that runs on your machine, keeps its state local, and gives you a visual place to build the work.

## Requirements

- macOS 14 or newer
- Xcode command line tools or Xcode
- Node.js 20 or newer
- npm
- Ollama for local model support
- Docker only if you want local semantic memory through Qdrant

Install the JavaScript dependencies once:

```bash
npm install
```

## Run Nexus

Build and open the native app:

```bash
./run.sh
```

Build without opening:

```bash
./run.sh --no-open
```

The script creates:

```text
native-macos/dist/Nexus.app
```

Open the Swift package directly when you want to work in Xcode:

```bash
open native-macos/Package.swift
```

Select the `LocalWorkflowStudioNative` scheme, then build and run.

## Local Engine

The app starts the engine automatically when needed. For engine-only development, run:

```bash
npm start
```

Health check:

```text
http://127.0.0.1:3131/health
```

Core routes:

```text
POST /node/generate
POST /node/save
GET  /node/list
POST /node/run
POST /nex/complete
POST /brain/prepare
GET  /memory/health
```

Supported workflow primitives:

- Browser
- Filesystem
- Shell
- HTTP
- MCP
- AI inference

## Local AI

Nexus uses Ollama by default.

```bash
npm run model:serve
npm run model:pull
```

`npm run model:pull` downloads:

```text
qwen2.5-coder:1.5b
nomic-embed-text
```

The engine default is `qwen2.5-coder:7b`. Pull it when you want the default model available:

```bash
ollama pull qwen2.5-coder:7b
```

Use a smaller model for lighter machines:

```bash
OLLAMA_MODEL=qwen2.5-coder:1.5b npm start
```

Inside the app, the Nex Brain view can prepare and switch between Ollama, LM Studio, and OpenAI-compatible providers.

## Memory

Semantic memory is optional. Start Qdrant when you want Nexus to store and retrieve local workflow context.

```bash
npm run memory:pull
npm run memory:start
```

Dashboard:

```text
http://127.0.0.1:6333/dashboard
```

Stop memory:

```bash
npm run memory:stop
```

Local storage:

```text
./qdrant_storage
```

## Development

Run the Node runtime tests:

```bash
npm test
```

Run native model tests:

```bash
cd native-macos
swift run LocalWorkflowStudioNativeModelTests
```

Run native integration tests:

```bash
cd native-macos
swift run LocalWorkflowStudioNativeIntegrationTests
```

Build the app bundle directly:

```bash
cd native-macos
./scripts/build-app.sh
```

## Project Shape

```text
src/                         Node workflow engine
tests/                       Engine tests
native-macos/                SwiftUI macOS app
native-macos/scripts/        App bundle build script
docs/                        Design, implementation, and QA notes
docker-compose.yml           Optional Qdrant memory service
```

## Environment

Most contributors do not need to set environment variables. These are available when you need control:

```text
PORT                         Engine port, default 3131
OLLAMA_MODEL                 Planner model, default qwen2.5-coder:7b
OLLAMA_BASE_URL              Ollama URL, default http://127.0.0.1:11434
NEXUS_ENGINE_ROOT            Override engine path for the native app
NEXUS_NODE_STORE             Override saved-node SQLite path
NEXUS_MEMORY_ENABLED=0       Disable Qdrant memory
NEXUS_QDRANT_URL             Qdrant HTTP URL, default http://127.0.0.1:6333
```
