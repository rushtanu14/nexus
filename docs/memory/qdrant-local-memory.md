# Local Qdrant Memory

Nexus stores semantic memory in a local Qdrant container. The container binds to
localhost only and persists data in `./qdrant_storage`, which is ignored by Git.

## Start Qdrant

```bash
npm run memory:pull
npm run memory:start
```

Endpoints:

- REST API: `http://127.0.0.1:6333`
- Web UI: `http://127.0.0.1:6333/dashboard`
- gRPC API: `localhost:6334`

The equivalent direct Docker command is:

```bash
docker run -p 127.0.0.1:6333:6333 -p 127.0.0.1:6334:6334 \
  -v "$(pwd)/qdrant_storage:/qdrant/storage:z" \
  qdrant/qdrant
```

## App Behavior

On memory reads or writes, Nexus creates the `nexus_memories_v1` collection if it
does not already exist. Memories use deterministic local embeddings by default,
so the memory layer stays local and does not require a cloud embedding service.

The Nex personal assistant uses this memory layer through `/nex/complete`.
Before each assistant completion, Nexus retrieves relevant local memories and
adds them to the model context. After the completion, it stores the user request
and Nex response as `prior_conversation` memories. If Qdrant is offline, Nex
continues without remembered context and reports `memory_status: "offline"`.

Required payload fields:

- `memory_type`
- `content`
- `timestamp`
- `source`
- `importance`
- `project`
- `tags`

Nexus adds operational metadata including `content_hash`, `embedding_model`,
`schema_version`, and `vector_size`. The `content_hash` field powers exact
deduplication before new memories are written.

Relevant memories are ranked with semantic similarity first, then importance and
recency. If Qdrant is not running, Nexus continues without memory context and
reports memory as offline in health/status responses.

## API

```bash
curl http://127.0.0.1:3131/memory/health
curl -X POST http://127.0.0.1:3131/memory/ensure
curl -X POST http://127.0.0.1:3131/memory/remember \
  -H "content-type: application/json" \
  -d '{"memory_type":"user_preference","content":"Keep Nexus memory local.","source":"manual","importance":0.9,"project":"nexus","tags":["privacy"]}'
curl -X POST http://127.0.0.1:3131/memory/query \
  -H "content-type: application/json" \
  -d '{"text":"local private memory","project":"nexus","limit":5}'
curl -X POST http://127.0.0.1:3131/nex/complete \
  -H "content-type: application/json" \
  -d '{"prompt":"What do you remember about my preferences?","brain":{"provider":"ollama","model":"qwen2.5-coder:7b"}}'
```

Configuration:

- `NEXUS_QDRANT_URL`, default `http://127.0.0.1:6333`
- `NEXUS_QDRANT_GRPC_URL`, default `localhost:6334`
- `NEXUS_MEMORY_COLLECTION`, default `nexus_memories_v1`
- `NEXUS_MEMORY_VECTOR_SIZE`, default `64`
- `NEXUS_MEMORY_ENABLED=0` disables memory calls
