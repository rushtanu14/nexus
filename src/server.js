import http from "node:http";
import express from "express";
import { executeNode } from "./executor.js";
import { generateNode, OLLAMA_BASE_URL, OLLAMA_MODEL } from "./generator.js";
import { createLifePlan } from "./life-assistant.js";
import { createMemoryStore } from "./memory-store.js";
import { listServers, registerServer, scrapeServer } from "./mcp-registry.js";
import { listNodes, saveNode } from "./node-store.js";

export function createApp() {
  const app = express();
  app.use(express.json());

  app.get("/health", asyncRoute(async (_request, response) => {
    response.json({ ok: true, ollama: await ollamaStatus(), model: OLLAMA_MODEL, qdrant: await memoryStatus() });
  }));
  app.post("/node/generate", asyncRoute(async (request, response) => {
    const intent = request.body.intent;
    const project = request.body.project ?? request.body.context?.project ?? "nexus";
    const memory = await optionalMemoryContext(intent, { project, source: "node/generate" });
    const node = await generateNode(intent, { ...(request.body.context ?? {}), memories: memory.memories });
    await optionalRemember({
      memory_type: "workflow",
      content: generatedNodeMemory(intent, node),
      source: "node/generate",
      importance: 0.45,
      project,
      tags: ["workflow", "generated-node"]
    });
    response.json(node);
  }));
  app.post("/node/save", asyncRoute(async (request, response) => {
    await saveNode(request.body.node);
    response.json({ id: request.body.node.id });
  }));
  app.get("/node/list", asyncRoute(async (_request, response) => {
    response.json(await listNodes());
  }));
  app.post("/node/run", asyncRoute(async (request, response) => {
    const result = await executeNode(request.body.node, request.body.context ?? {});
    await optionalRemember({
      memory_type: "task_history",
      content: nodeRunMemory(request.body.node, result),
      source: "node/run",
      importance: 0.35,
      project: request.body.project ?? request.body.context?.project ?? "nexus",
      tags: ["task-history", "node-run"]
    });
    response.json(result);
  }));
  app.post("/life/plan", asyncRoute(async (request, response) => {
    const text = request.body.text ?? request.body.notes ?? "";
    const project = request.body.project ?? "nexus";
    const memory = await optionalMemoryContext(text, { project, source: "life/plan" });
    const plan = createLifePlan(text);
    await optionalRemember({
      memory_type: "workflow",
      content: lifePlanMemory(plan),
      source: "life/plan",
      importance: plan.stats.tasks > 0 ? 0.55 : 0.35,
      project,
      tags: ["life-plan", "workflow"]
    });
    response.json({ ...plan, memory_context: memory.memories, memory_status: memory.status });
  }));
  app.get("/memory/health", asyncRoute(async (_request, response) => {
    response.json(await createMemoryStore().health());
  }));
  app.post("/memory/ensure", asyncRoute(async (_request, response) => {
    response.json(await createMemoryStore().ensureCollection());
  }));
  app.post("/memory/query", asyncRoute(async (request, response) => {
    response.json(await createMemoryStore().query(request.body.text ?? request.body.query ?? "", request.body));
  }));
  app.post("/memory/remember", asyncRoute(async (request, response) => {
    response.json(await createMemoryStore().remember(request.body.memory ?? request.body));
  }));
  app.post("/mcp/register", asyncRoute(async (request, response) => {
    await registerServer(request.body.app, request.body.url);
    await optionalRemember({
      memory_type: "automation",
      content: `Registered MCP server ${request.body.app} at ${request.body.url}.`,
      source: "mcp/register",
      importance: 0.4,
      project: request.body.project ?? "nexus",
      tags: ["mcp", "automation"]
    });
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

async function memoryStatus() {
  return createMemoryStore({ timeoutMs: 200 }).health();
}

async function optionalMemoryContext(text, { project, source }) {
  if (!String(text ?? "").trim()) return { status: "empty", memories: [] };
  try {
    const result = await createMemoryStore({ timeoutMs: 250 }).contextForRequest(text, { limit: 5, project });
    return { status: result.ok ? "ok" : result.reason ?? "unavailable", memories: result.memories ?? [], context: result.context ?? "", source };
  } catch (error) {
    return { status: "offline", memories: [], error: error.message, source };
  }
}

async function optionalRemember(memory) {
  if (!String(memory?.content ?? "").trim()) return { status: "empty" };
  try {
    const result = await createMemoryStore({ timeoutMs: 250 }).remember(memory);
    return { status: result.ok ? "ok" : result.reason ?? "unavailable", ...result };
  } catch (error) {
    return { status: "offline", error: error.message };
  }
}

function generatedNodeMemory(intent, node) {
  if (node?.error) return `Could not generate a Nexus node for: ${intent}. Reason: ${node.reason ?? node.error}.`;
  return `Generated Nexus node "${node?.meta?.label ?? node?.meta?.action ?? "unknown"}" for request: ${intent}.`;
}

function nodeRunMemory(node, result) {
  const label = node?.meta?.label ?? node?.meta?.action ?? node?.id ?? "unknown node";
  const status = result?.ok === false ? "failed" : "completed";
  return `Ran Nexus node "${label}" with status ${status}.`;
}

function lifePlanMemory(plan) {
  return `Created life plan "${plan.title}" with ${plan.stats.tasks} tasks, ${plan.stats.questions} questions, and ${plan.stats.automations} suggested automations. Brief: ${plan.brief}`;
}

async function ensureMemoryOnLaunch() {
  try {
    await createMemoryStore({ timeoutMs: 500 }).ensureCollection();
  } catch {
    // Qdrant is optional at launch; requests report offline memory until it starts.
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
  createServer().listen(port, "127.0.0.1", () => {
    console.log(`Nexus workflow engine listening on http://127.0.0.1:${port}`);
    ensureMemoryOnLaunch();
  });
}
