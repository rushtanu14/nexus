import http from "node:http";
import { execFile } from "node:child_process";
import fs from "node:fs";
import { promisify } from "node:util";
import express from "express";
import { NexAssistant } from "./assistant/NexAssistant.js";
import { ActionInferrer } from "./echo/ActionInferrer.js";
import { buildEchoActions, runEchoAction } from "./echo-actions.js";
import { executeNode } from "./executor.js";
import { generateNode, OLLAMA_BASE_URL, OLLAMA_MODEL } from "./generator.js";
import { createLifePlan } from "./life-assistant.js";
import { createMemoryStore } from "./memory-store.js";
import { listServers, registerServer, scrapeServer } from "./mcp-registry.js";
import { clearNodes, deleteNode, listNodes, saveNode } from "./node-store.js";
import { ensureOllamaReady, ollamaBaseUrl as runtimeOllamaBaseUrl, ollamaChatWithFallback, ollamaHealthCheck } from "./ollama-runtime.js";
import { PetSpawner } from "./pets/PetSpawner.js";
import { actionStore } from "./store/ActionStore.js";
import { BRIDGES } from "../scripts/nexus-mcp-bridge.mjs";

const MCP_HOST = process.env.NEXUS_MCP_HOST ?? "127.0.0.1";
const BUILT_IN_MCP_CONNECTORS = Object.entries(BRIDGES).map(([app, bridge]) => ({
  app,
  label: {
    gmail: "Gmail",
    "google-workspace": "Google Calendar",
    "google-drive": "Google Drive",
    slack: "Slack",
    notion: "Notion"
  }[app] ?? app,
  provider: app === "gmail" || app === "google-workspace" || app === "google-drive" ? "google" : app,
  url: `http://${MCP_HOST}:${bridge.port}`,
  connectUrl: `http://${MCP_HOST}:${bridge.port}/connect`,
  healthUrl: `http://${MCP_HOST}:${bridge.port}/health`,
  testUrl: `http://${MCP_HOST}:${bridge.port}/test`,
  tools: bridge.tools.map((tool) => tool.name)
}));

const execFileAsync = promisify(execFile);

export function createApp() {
  registerBuiltInMcpServers();
  const app = express();
  const complete = (prompt, brain) => completeWithNex(prompt, brain, "");
  const inferrer = new ActionInferrer({ store: actionStore, complete });
  const petSpawner = new PetSpawner({ store: actionStore });
  const assistant = new NexAssistant({ store: actionStore, complete, spawner: petSpawner });
  app.use(express.json({ limit: process.env.NEXUS_JSON_LIMIT ?? "2mb" }));

  app.get("/health", asyncRoute(async (_request, response) => {
    response.json({
      ok: true,
      ollama: await ollamaStatus(),
      model: OLLAMA_MODEL,
      qdrant: await memoryStatus(),
      features: {
        echoActions: true,
        echoMCPWorkflows: true,
        echoRealtime: true,
        echoPets: true,
        echoAssistantQueue: true
      }
    });
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
  app.post("/echo/actions", asyncRoute(async (request, response) => {
    const sessionId = request.body.sessionId ?? "default";
    const transcript = request.body.transcript ?? "";
    const notes = request.body.notes ?? "";
    const title = request.body.title ?? "Echo notes";
    const project = request.body.project ?? "nexus";
    const text = [title, notes, transcript].filter(Boolean).join("\n\n");
    const memory = await optionalMemoryContext(text, { project, source: "echo/actions" });
    const actions = buildEchoActions({ transcript, notes, title, memory: memory.context });
    await optionalRemember({
      memory_type: "automation",
      content: `Built ${actions.length} Echo MCP action suggestion(s) for "${title}".`,
      source: "echo/actions",
      importance: actions.length > 0 ? 0.5 : 0.25,
      project,
      tags: ["echo", "mcp", "automation"]
    });
    for (const action of actions) actionStore.upsertAction({ ...action, status: action.status ?? "pending" }, { sessionId });
    response.json({ actions, memory_status: memory.status, snapshot: actionStore.snapshot(sessionId) });
  }));
  app.post("/echo/chunk", asyncRoute(async (request, response) => {
    const sessionId = request.body.sessionId ?? "default";
    const text = request.body.text ?? request.body.chunk ?? "";
    const title = request.body.title ?? "Echo meeting";
    const notes = request.body.notes ?? "";
    actionStore.appendTranscriptChunk({ sessionId, text });
    const actions = await inferrer.handleChunk({ sessionId, text, title, notes, brain: request.body.brain ?? {} });
    response.json({ ok: true, actions, snapshot: actionStore.snapshot(sessionId) });
  }));
  app.post("/echo/infer", asyncRoute(async (request, response) => {
    const sessionId = request.body.sessionId ?? "default";
    const actions = await inferrer.infer({
      sessionId,
      title: request.body.title ?? "Echo meeting",
      notes: request.body.notes ?? "",
      brain: request.body.brain ?? {}
    });
    response.json({ actions, snapshot: actionStore.snapshot(sessionId) });
  }));
  app.get("/echo/dashboard", asyncRoute(async (request, response) => {
    response.json(actionStore.snapshot(request.query.sessionId ?? "default"));
  }));
  app.post("/echo/action/dispatch", asyncRoute(async (request, response) => {
    const sessionId = request.body.sessionId ?? request.body.action?.sessionId ?? "default";
    const action = actionStore.upsertAction({ ...request.body.action, status: "pending" }, { sessionId });
    const pet = petSpawner.spawn(action);
    response.json({ ok: true, pet, action, snapshot: actionStore.snapshot(sessionId) });
  }));
  app.post("/echo/action/cancel", asyncRoute(async (request, response) => {
    const sessionId = request.body.sessionId ?? "default";
    const action = petSpawner.cancel(request.body.actionId, sessionId) ?? actionStore.cancelAction(request.body.actionId, { sessionId });
    response.json({ ok: Boolean(action), action, snapshot: actionStore.snapshot(sessionId) });
  }));
  app.post("/echo/assistant", asyncRoute(async (request, response) => {
    const sessionId = request.body.sessionId ?? "default";
    const result = await assistant.handleMessage({ sessionId, message: request.body.message ?? "", brain: request.body.brain ?? {} });
    response.json({ ok: true, ...result });
  }));
  app.post("/echo/action/run", asyncRoute(async (request, response) => {
    const result = await runEchoAction(request.body.action, { registeredServers: await listServers() });
    await optionalRemember({
      memory_type: "automation",
      content: `Echo MCP action "${request.body.action?.title ?? "unknown"}" status: ${result.status}.`,
      source: "echo/action/run",
      importance: 0.35,
      project: request.body.project ?? "nexus",
      tags: ["echo", "mcp", "action-run"]
    });
    response.json(result);
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
  app.post("/brain/health", asyncRoute(async (request, response) => {
    response.json(await brainHealth(request.body.brain ?? {}));
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
  app.get("/mcp/catalog", asyncRoute(async (_request, response) => {
    response.json({ connectors: BUILT_IN_MCP_CONNECTORS, registered: await listServers() });
  }));
  app.get("/mcp/status", asyncRoute(async (_request, response) => {
    response.json({
      connectors: await Promise.all(BUILT_IN_MCP_CONNECTORS.map(connectorStatus)),
      registered: await listServers()
    });
  }));
  app.get("/mcp/connect/:app", asyncRoute(async (request, response) => {
    const connector = connectorForApp(request.params.app);
    const payload = await fetchConnectorJson(`${connector.connectUrl}?format=json`);
    response.json({ ...payload, app: connector.app, label: connector.label });
  }));
  app.post("/mcp/test/:app", asyncRoute(async (request, response) => {
    const connector = connectorForApp(request.params.app);
    response.json(await fetchConnectorJson(connector.testUrl));
  }));

  app.use((_request, response) => response.status(404).json({ error: "not_found" }));
  app.use((error, _request, response, _next) => response.status(400).json({ error: error.message }));
  return app;
}

registerBuiltInMcpServers();

function registerBuiltInMcpServers() {
  for (const connector of BUILT_IN_MCP_CONNECTORS) {
    registerServer(connector.app, connector.url);
  }
}

function connectorForApp(app) {
  const connector = BUILT_IN_MCP_CONNECTORS.find((item) => item.app === app);
  if (!connector) throw new Error(`Unknown MCP connector: ${app}`);
  return connector;
}

async function connectorStatus(connector) {
  try {
    const health = await fetchConnectorJson(connector.healthUrl, { timeoutMs: 800 });
    return {
      ...connector,
      reachable: true,
      ok: Boolean(health.ok),
      auth: health.auth,
      state: health.auth?.connected ? "connected" : health.auth?.connectReady ? "ready" : "setup_needed",
      error: null
    };
  } catch (error) {
    return {
      ...connector,
      reachable: false,
      ok: false,
      auth: null,
      state: "offline",
      error: error.message
    };
  }
}

async function fetchConnectorJson(url, { timeoutMs = 5000 } = {}) {
  const response = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};
  if (!response.ok || payload.error) {
    throw new Error(payload.error?.message ?? payload.error ?? `MCP connector request failed with HTTP ${response.status}`);
  }
  return payload;
}

async function ollamaStatus() {
  try {
    const timeoutMs = Number(process.env.NEXUS_HEALTH_TIMEOUT_MS ?? 2000);
    const response = await fetch(`${OLLAMA_BASE_URL}/api/tags`, { signal: AbortSignal.timeout(timeoutMs) });
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
    const baseUrl = runtimeOllamaBaseUrl(brain.baseUrl);
    try {
      const result = await ollamaChatWithFallback({
        baseUrl,
        preferredModel: model,
        timeoutMs: Number(process.env.OLLAMA_TIMEOUT_MS ?? 120000),
        body: {
          stream: false,
          messages: [{ role: "system", content: system }, { role: "user", content: prompt }]
        }
      });
      if (!result.payload.message?.content) throw new Error("Nex model returned no content");
      return result.payload.message.content;
    } catch (error) {
      console.error("[nexus] Nex local model request failed", error.details ?? error);
      throw new Error("Local models unavailable - check system resources");
    }
  }

  const baseUrl = String(brain.baseUrl || (provider === "lmstudio" ? "http://127.0.0.1:1234/v1" : "https://api.openai.com/v1")).replace(/\/$/, "");
  const headers = { "content-type": "application/json" };
  if (brain.apiKey) headers.authorization = `Bearer ${brain.apiKey}`;
  const candidates = openAICompatibleModelCandidates(model, provider);
  const errors = [];
  for (const candidate of candidates) {
    const response = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST",
      headers,
      body: JSON.stringify({ model: candidate, messages: [{ role: "system", content: system }, { role: "user", content: prompt }] }),
      signal: AbortSignal.timeout(Number(process.env.NEXUS_CHAT_TIMEOUT_MS ?? 120000))
    });
    if (!response.ok) {
      const detail = await response.text();
      errors.push(`${candidate}: HTTP ${response.status}: ${detail}`);
      console.error(`[nexus] ${provider} model failed; trying fallback if available`, errors.at(-1));
      continue;
    }
    const payload = await response.json();
    if (payload.choices?.[0]?.message?.content) return payload.choices[0].message.content;
    errors.push(`${candidate}: no content`);
  }
  console.error("[nexus] Nex compatible model request failed", errors);
  throw new Error(provider === "lmstudio" ? "Local models unavailable - check system resources" : "Configured AI provider is unavailable");
}

async function prepareBrain(brain) {
  const provider = brain.provider ?? "ollama";
  const model = brain.model || OLLAMA_MODEL;
  if (provider === "ollama") {
    const baseUrl = runtimeOllamaBaseUrl(brain.baseUrl);
    const ready = await ensureOllamaReady({ baseUrl, model });
    const health = await ollamaHealthCheck({ baseUrl, model });
    return `Prepared ${health.model || ready.model} with Ollama${health.cpuOnly ? " (CPU mode - GPU unavailable)" : ""}`;
  }
  if (provider === "lmstudio") {
    const executable = lmStudioExecutable();
    const baseUrl = String(brain.baseUrl || "http://127.0.0.1:1234/v1").replace(/\/$/, "");
    if (!(await isOpenAICompatibleReachable(baseUrl))) {
      await runLms(executable, ["server", "start"]);
      await waitForOpenAICompatible(baseUrl, Number(process.env.NEXUS_LMSTUDIO_START_TIMEOUT_MS ?? 8000));
    }
    if (process.env.NEXUS_LMSTUDIO_PULL === "1") {
      await runLms(executable, ["get", model, "--yes"], { timeout: Number(process.env.NEXUS_PREPARE_TIMEOUT_MS ?? 600000) });
    }
    await runLms(executable, ["load", model, "--yes"], { timeout: Number(process.env.NEXUS_LMSTUDIO_LOAD_TIMEOUT_MS ?? 120000) });
    return `Prepared ${model} with LM Studio`;
  }
  return "OpenAI-compatible providers do not require local preparation";
}

async function brainHealth(brain) {
  const provider = brain.provider ?? "ollama";
  const model = brain.model || OLLAMA_MODEL;
  if (provider === "ollama") return ollamaHealthCheck({ baseUrl: runtimeOllamaBaseUrl(brain.baseUrl), model });
  if (provider === "lmstudio") return { ok: await isOpenAICompatibleReachable(String(brain.baseUrl || "http://127.0.0.1:1234/v1").replace(/\/$/, "")), model };
  return { ok: true, model, remote: true };
}

function openAICompatibleModelCandidates(preferredModel, provider) {
  const configured = String(process.env.NEXUS_COMPATIBLE_FALLBACK_MODELS ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  const localDefaults = provider === "lmstudio" ? ["qwen2.5-coder-7b-instruct", "llama-3.2-3b-instruct", "gemma-3-4b-it"] : [];
  return [...new Set([preferredModel, ...configured, ...localDefaults].filter(Boolean))];
}

function lmStudioExecutable() {
  const configured = process.env.NEXUS_LMS_PATH;
  const home = process.env.HOME;
  const candidates = [
    configured,
    `${home}/.lmstudio/bin/lms`,
    "/opt/homebrew/bin/lms",
    "/usr/local/bin/lms"
  ].filter(Boolean);
  return candidates.find((candidate) => {
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return true;
    } catch {
      return false;
    }
  }) ?? "lms";
}

async function runLms(executable, args, options = {}) {
  if (executable === "lms") return execFileAsync("/usr/bin/env", ["lms", ...args], options);
  return execFileAsync(executable, args, options);
}

async function waitForOpenAICompatible(baseUrl, timeoutMs) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    if (await isOpenAICompatibleReachable(baseUrl)) return true;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  return false;
}

async function isOpenAICompatibleReachable(baseUrl) {
  try {
    const response = await fetch(`${baseUrl}/models`, { signal: AbortSignal.timeout(500) });
    return response.ok;
  } catch {
    return false;
  }
}

function ollamaBaseUrl(configuredBaseUrl) {
  return runtimeOllamaBaseUrl(configuredBaseUrl);
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
  const host = process.env.HOST ?? "127.0.0.1";
  createServer().listen(port, host, () => {
    console.log(`Nexus workflow engine listening on http://${host}:${port}`);
    ensureMemoryOnLaunch();
  });
}
