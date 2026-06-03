import http from "node:http";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import express from "express";
import { executeNode } from "./executor.js";
import { generateNode, OLLAMA_BASE_URL, OLLAMA_MODEL } from "./generator.js";
import { createLifePlan } from "./life-assistant.js";
import { createMemoryStore } from "./memory-store.js";
import { listServers, registerServer, scrapeServer } from "./mcp-registry.js";
import { clearNodes, deleteNode, listNodes, saveNode } from "./node-store.js";

const execFileAsync = promisify(execFile);

export function createApp() {
  const app = express();
  app.use(express.json({ limit: process.env.NEXUS_JSON_LIMIT ?? "2mb" }));

  app.get("/health", asyncRoute(async (_request, response) => {
    response.json({ ok: true, ollama: await ollamaStatus(), model: OLLAMA_MODEL, qdrant: await memoryStatus() });
  }));
  app.post("/node/generate", asyncRoute(async (request, response) => {
    const intent = request.body.intent;
    const project = request.body.project ?? request.body.context?.project ?? "nexus";
    const node = await generateNode(intent, request.body.context ?? {});
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
  app.post("/node/delete", asyncRoute(async (request, response) => {
    await deleteNode(request.body.id);
    response.json({ ok: true });
  }));
  app.post("/node/clear", asyncRoute(async (_request, response) => {
    await clearNodes();
    response.json({ ok: true });
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
  app.post("/nex/complete", asyncRoute(async (request, response) => {
    const prompt = String(request.body.prompt ?? "");
    if (!prompt.trim()) throw new Error("prompt is required");
    const project = request.body.project ?? "nexus";
    const memory = await optionalMemoryContext(prompt, { project, source: "nex/complete" });
    const completion = await completeWithNex(prompt, request.body.brain ?? {}, memory.context);
    await optionalRemember({
      memory_type: "prior_conversation",
      content: `User asked Nex: ${memoryText(prompt)}`,
      source: "nex/complete",
      importance: 0.5,
      project,
      tags: ["assistant", "user-request"]
    });
    await optionalRemember({
      memory_type: "prior_conversation",
      content: `Nex answered: ${memoryText(completion)}`,
      source: "nex/complete",
      importance: 0.4,
      project,
      tags: ["assistant", "response"]
    });
    response.json({ completion, memory_status: memory.status });
  }));
  app.post("/brain/prepare", asyncRoute(async (request, response) => {
    response.json({ status: await prepareBrain(request.body.brain ?? {}) });
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

function memoryText(value, maxLength = 2400) {
  const text = String(value ?? "").trim().replace(/\s+/g, " ");
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength - 20).trim()}... [truncated]`;
}

async function completeWithNex(prompt, brain, memoryContext) {
  const provider = brain.provider ?? "ollama";
  const model = brain.model || OLLAMA_MODEL;
  const system = [
    "You are Nex, the local Nexus personal assistant.",
    "Answer concisely and use remembered context only when it is relevant.",
    memoryContext ? `Relevant local memory:\n${memoryContext}` : "No relevant local memory was available."
  ].join("\n\n");

  if (provider === "ollama") {
    const baseUrl = ollamaBaseUrl(brain.baseUrl);
    const response = await fetch(`${baseUrl}/api/chat`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ model, stream: false, messages: [{ role: "system", content: system }, { role: "user", content: prompt }] }),
      signal: AbortSignal.timeout(Number(process.env.OLLAMA_TIMEOUT_MS ?? 120000))
    });
    if (!response.ok) throw new Error(`Nex model request failed with HTTP ${response.status}: ${await response.text()}`);
    const payload = await response.json();
    if (!payload.message?.content) throw new Error("Nex model returned no content");
    return payload.message.content;
  }

  const baseUrl = String(brain.baseUrl || (provider === "lmstudio" ? "http://127.0.0.1:1234/v1" : "https://api.openai.com/v1")).replace(/\/$/, "");
  const headers = { "content-type": "application/json" };
  if (brain.apiKey) headers.authorization = `Bearer ${brain.apiKey}`;
  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers,
    body: JSON.stringify({ model, messages: [{ role: "system", content: system }, { role: "user", content: prompt }] }),
    signal: AbortSignal.timeout(Number(process.env.NEXUS_CHAT_TIMEOUT_MS ?? 120000))
  });
  if (!response.ok) throw new Error(`Nex model request failed with HTTP ${response.status}: ${await response.text()}`);
  const payload = await response.json();
  if (!payload.choices?.[0]?.message?.content) throw new Error("Nex model returned no content");
  return payload.choices[0].message.content;
}

async function prepareBrain(brain) {
  const provider = brain.provider ?? "ollama";
  const model = brain.model || OLLAMA_MODEL;
  if (provider === "ollama") {
    const baseUrl = ollamaBaseUrl(brain.baseUrl);
    const response = await fetch(`${baseUrl}/api/pull`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ model, stream: false }),
      signal: AbortSignal.timeout(Number(process.env.NEXUS_PREPARE_TIMEOUT_MS ?? 600000))
    });
    if (!response.ok) throw new Error(`Ollama could not prepare ${model}: ${await response.text()}`);
    return `Prepared ${model} with Ollama`;
  }
  if (provider === "lmstudio") {
    const executable = process.env.NEXUS_LMS_PATH || `${process.env.HOME}/.lmstudio/bin/lms`;
    await execFileAsync(executable, ["server", "start"]);
    await execFileAsync(executable, ["get", model, "--yes"], { timeout: Number(process.env.NEXUS_PREPARE_TIMEOUT_MS ?? 600000) });
    await execFileAsync(executable, ["load", model, "--yes"], { timeout: Number(process.env.NEXUS_PREPARE_TIMEOUT_MS ?? 600000) });
    return `Prepared ${model} with LM Studio`;
  }
  return "OpenAI-compatible providers do not require local preparation";
}

function ollamaBaseUrl(configuredBaseUrl) {
  const configured = String(configuredBaseUrl ?? "").trim();
  if (!configured || configured.includes("api.openai.com")) return OLLAMA_BASE_URL;
  return configured.replace(/\/$/, "");
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
