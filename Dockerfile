FROM node:22-bookworm-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates g++ make python3 \
    && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY src ./src

ENV HOST=0.0.0.0 \
    PORT=3131 \
    NEXUS_NODE_STORE=/data/nodes.sqlite \
    NEXUS_MEMORY_ENABLED=1 \
    NEXUS_QDRANT_URL=http://qdrant:6333 \
    NEXUS_QDRANT_GRPC_URL=qdrant:6334 \
    OLLAMA_BASE_URL=http://ollama:11434 \
    OLLAMA_MODEL=qwen2.5-coder:1.5b

VOLUME ["/data"]
EXPOSE 3131

CMD ["node", "src/server.js"]
