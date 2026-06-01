import http from "node:http";
import express from "express";
import { executeNode } from "./executor.js";
import { generateNode, OLLAMA_BASE_URL, OLLAMA_MODEL } from "./generator.js";
import { createLifePlan } from "./life-assistant.js";
import { listServers, registerServer, scrapeServer } from "./mcp-registry.js";
import { listNodes, saveNode } from "./node-store.js";

export function createApp() {
  const app = express();
  app.use(express.json());

  app.get("/health", asyncRoute(async (_request, response) => {
    response.json({ ok: true, ollama: await ollamaStatus(), model: OLLAMA_MODEL });
  }));
  app.post("/node/generate", asyncRoute(async (request, response) => {
    response.json(await generateNode(request.body.intent, request.body.context ?? {}));
  }));
  app.post("/node/save", asyncRoute(async (request, response) => {
    await saveNode(request.body.node);
    response.json({ id: request.body.node.id });
  }));
  app.get("/node/list", asyncRoute(async (_request, response) => {
    response.json(await listNodes());
  }));
  app.post("/node/run", asyncRoute(async (request, response) => {
    response.json(await executeNode(request.body.node, request.body.context ?? {}));
  }));
  app.post("/life/plan", asyncRoute(async (request, response) => {
    response.json(createLifePlan(request.body.text ?? request.body.notes ?? ""));
  }));
  app.post("/mcp/register", asyncRoute(async (request, response) => {
    await registerServer(request.body.app, request.body.url);
    response.json({ found: (await scrapeServer(request.body.app)).length });
  }));
  app.get("/mcp/list", asyncRoute(async (_request, response) => {
    response.json(await listServers());
  }));

  app.use((_request, response) => response.status(404).json({ error: "not_found" }));
  app.use((error, _request, response, _next) => response.status(400).json({ error: error.message }));
  return app;
}

async function ollamaStatus() {
  try {
    const response = await fetch(`${OLLAMA_BASE_URL}/api/tags`, { signal: AbortSignal.timeout(500) });
    return response.ok;
  } catch {
    return false;
  }
}

export function createServer() {
  return http.createServer(createApp());
}

function asyncRoute(handler) {
  return (request, response, next) => Promise.resolve(handler(request, response)).catch(next);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const port = Number(process.env.PORT ?? 3131);
  createServer().listen(port, "127.0.0.1", () => console.log(`Nexus workflow engine listening on http://127.0.0.1:${port}`));
}
