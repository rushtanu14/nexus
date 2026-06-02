<div align="center">

<img width="276" height="118" alt="Nexus" src="https://github.com/user-attachments/assets/fffb4645-d719-4988-938a-bef235ac5283" />

developing the native macOS workspace for local workflows, agents, memory, and automation

<br>

<p align="center">
  <img height="150" src="https://github.com/user-attachments/assets/93917c1c-65bd-415e-8ed2-681c5e43e7ee" />
  <img height="150" src="https://github.com/user-attachments/assets/0faa7179-e48c-43e2-ad4d-d46a86379c49" />
  <img height="150" src="https://github.com/user-attachments/assets/b9fd521b-35d3-4827-99c0-bfa3358fc044" />
  <img height="150" src="https://github.com/user-attachments/assets/9ef93fdd-6f96-43b2-af54-99014ca28caa" />
</p>

</div>

## Quick Start

### Xcode

```bash
open native-macos/Package.swift
```

Select:

```text
LocalWorkflowStudioNative
```

Build and run.

### Terminal

```bash
./run.sh
```

Without launching the app:

```bash
./run.sh --no-open
```

### App Bundle

```bash
cd native-macos
./scripts/build-app.sh
open dist/Nexus.app
```

## Local Workflow Engine

```bash
npm install
npm start
```

Local API:

```text
http://127.0.0.1:3131
```

Available adapters:

* Browser
* MCP
* Filesystem
* Shell
* HTTP
* AI Inference

## Memory

Nexus supports local semantic memory through Qdrant.

```bash
npm run memory:pull
npm run memory:start
```

Endpoints:

```text
http://127.0.0.1:6333
http://127.0.0.1:6333/dashboard
```

Storage:

```text
./qdrant_storage
```

Collection:

```text
nexus_memories_v1
```

## Local Model

Nexus defaults to the smaller Qwen coder model so it can run on 8 GB Macs.

```bash
npm run model:pull
```

The 7B model remains usable by setting `OLLAMA_MODEL=qwen2.5-coder:7b` when the machine has enough memory headroom.

## Development

### Native Tests

```bash
cd native-macos
swift run LocalWorkflowStudioNativeModelTests
```

### Integration Tests

```bash
cd native-macos
swift run LocalWorkflowStudioNativeIntegrationTests
```

### Workflow Runtime

```bash
npm test
```
