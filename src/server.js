import http from "node:http";
import { execFile } from "node:child_process";
import fs from "node:fs";
import { promisify } from "node:util";
import express from "express";
import { NexAssistant } from "./assistant/NexAssistant.js";
import { ActionInferrer } from "./echo/ActionInferrer.js";
import { buildEchoActions, runEchoAction } from "./echo-actions.js";
import { createCalendarEvent, inferSchedule, listCalendarEvents, resetCalendar } from "./calendar-store.js";
import { addDailyTask, listDailyTasks, resetDailyTasks, toggleDailyTask } from "./daily-task-store.js";
import { executeNode } from "./executor.js";
import { generateNode, OLLAMA_BASE_URL, OLLAMA_MODEL } from "./generator.js";
import { createLifePlan } from "./life-assistant.js";
import { createMemoryStore } from "./memory-store.js";
import { authenticateConnector, configureConnector, listConnectors, listServers, registerServer, scrapeServer } from "./mcp-registry.js";
import { clearNodes, deleteNode, listNodes, saveNode } from "./node-store.js";
import { PetSpawner } from "./pets/PetSpawner.js";
import { actionStore } from "./store/ActionStore.js";

const execFileAsync = promisify(execFile);

export function createApp() {
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
        echoAssistantQueue: true,
        calendarSchedules: true,
        mcpConnectorAuth: true,
        dailyDashboardTasks: true
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
    const result = runEchoAction(request.body.action, { registeredServers: await listServers() });
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
  app.get("/calendar/events", asyncRoute(async (_request, response) => {
    response.json({ events: await listCalendarEvents() });
  }));
  app.post("/calendar/infer", asyncRoute(async (request, response) => {
    const rawContext = [
      request.body.transcript,
      request.body.spoken ?? request.body.message,
      typeof request.body.connectorContext === "string" ? request.body.connectorContext : JSON.stringify(request.body.connectorContext ?? request.body.connectors ?? "")
    ].filter(Boolean).join("\n\n");
    const memory = await optionalMemoryContext(rawContext, { project: request.body.project ?? "nexus", source: "calendar/infer" });
    const schedule = await inferSchedule({
      title: request.body.title,
      transcript: request.body.transcript,
      spoken: request.body.spoken ?? request.body.message,
      connectorContext: [
        request.body.connectorContext ?? request.body.connectors,
        memory.context ? `Relevant local memory:\n${memory.context}` : ""
      ].filter(Boolean).join("\n\n")
    });
    await optionalRemember({
      memory_type: "workflow",
      content: `Inferred ${schedule.events.length} calendar event(s) for "${schedule.title}". Brief: ${schedule.brief}`,
      source: "calendar/infer",
      importance: schedule.events.length > 0 ? 0.55 : 0.3,
      project: request.body.project ?? "nexus",
      tags: ["calendar", "schedule", "mcp"]
    });
    response.json({ ...schedule, memory_status: memory.status });
  }));
  app.post("/calendar/event/create", asyncRoute(async (request, response) => {
    const event = await createCalendarEvent(request.body.event ?? request.body, { autoRun: request.body.autoRun !== false });
    response.json({ ok: event.status === "created" || event.status === "ready", event });
  }));
  app.post("/calendar/reset", asyncRoute(async (_request, response) => {
    response.json(await resetCalendar());
  }));
  app.get("/dashboard/tasks", asyncRoute(async (_request, response) => {
    response.json(await listDailyTasks());
  }));
  app.post("/dashboard/tasks/add", asyncRoute(async (request, response) => {
    response.json(await addDailyTask(request.body.title));
  }));
  app.post("/dashboard/tasks/toggle", asyncRoute(async (request, response) => {
    response.json(await toggleDailyTask(request.body.id));
  }));
  app.post("/dashboard/tasks/reset", asyncRoute(async (_request, response) => {
    response.json(await resetDailyTasks({ hard: true }));
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
    const toolResult = await maybeHandleNexToolCommand(prompt, { project, memoryContext: memory.context });
    if (toolResult) {
      response.json({ completion: toolResult, memory_status: memory.status, tool_used: true });
      return;
    }
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
  app.get("/mcp/registry", asyncRoute(async (_request, response) => {
    response.json({ connectors: await listConnectors() });
  }));
  app.post("/mcp/configure", asyncRoute(async (request, response) => {
    const connector = await configureConnector(request.body);
    await optionalRemember({
      memory_type: "automation",
      content: `Configured MCP connector ${connector.app} at ${connector.url}.`,
      source: "mcp/configure",
      importance: 0.45,
      project: request.body.project ?? "nexus",
      tags: ["mcp", "connector", "auth"]
    });
    response.json({ ok: true, connector });
  }));
  app.post("/mcp/authenticate", asyncRoute(async (request, response) => {
    const connector = await authenticateConnector(request.body);
    await optionalRemember({
      memory_type: "automation",
      content: `Authenticated MCP connector ${connector.app}.`,
      source: "mcp/authenticate",
      importance: 0.55,
      project: request.body.project ?? "nexus",
      tags: ["mcp", "connector", "auth"]
    });
    response.json({ ok: true, connector });
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

async function maybeHandleNexToolCommand(prompt, { project, memoryContext }) {
  const text = String(prompt ?? "").trim();
  const lower = text.toLowerCase();
  if (/\b(calendar|schedule|meeting|invite|event)\b/.test(lower) && /\b(add|create|schedule|book|infer|put|plan)\b/.test(lower)) {
    const schedule = await inferSchedule({
      title: "Nex calendar command",
      transcript: text,
      spoken: text,
      connectorContext: memoryContext ? `Relevant local memory:\n${memoryContext}` : ""
    });
    const created = [];
    if (/\b(add|create|schedule|book|put)\b/.test(lower)) {
      for (const event of schedule.events.slice(0, 3)) {
        created.push(await createCalendarEvent(event, { autoRun: true }));
      }
    }
    await optionalRemember({
      memory_type: "automation",
      content: `Nex handled a calendar command with ${schedule.events.length} inferred event(s) and ${created.length} created event(s).`,
      source: "nex/calendar-tool",
      importance: 0.55,
      project,
      tags: ["nex", "calendar", "tool"]
    });
    const lines = [
      `Calendar tool used. Inferred ${schedule.events.length} schedule item(s).`,
      created.length ? `Created or queued ${created.length} event(s):` : "No events were created because this was an infer-only request.",
      ...created.map((event) => `- ${event.title} — ${event.dateText} ${event.timeText} (${event.status})`),
      !created.length ? schedule.events.map((event) => `- ${event.title} — ${event.dateText} ${event.timeText}`).join("\n") : ""
    ].filter(Boolean);
    return lines.join("\n");
  }

  if (/\b(task|todo|daily)\b/.test(lower) && /\b(add|create|list|show|reset|clear)\b/.test(lower)) {
    if (/\b(reset|clear)\b/.test(lower)) {
      const snapshot = await resetDailyTasks({ hard: true });
      return `Daily tasks reset. ${snapshot.tasks.length} task(s) remain.`;
    }
    const title = text.replace(/^(add|create)\s+/i, "").replace(/\b(to|into)?\s*(daily tasks?|todo list)\b/ig, "").trim();
    if (/\b(add|create)\b/.test(lower) && title) {
      const snapshot = await addDailyTask(title);
      return `Added daily task. Current list:\n${snapshot.tasks.map((task) => `- ${task.status === "done" ? "[x]" : "[ ]"} ${task.title}`).join("\n")}`;
    }
    const snapshot = await listDailyTasks();
    return `Daily tasks:\n${snapshot.tasks.map((task) => `- ${task.status === "done" ? "[x]" : "[ ]"} ${task.title}`).join("\n") || "- No tasks yet."}`;
  }

  return null;
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
    const candidates = uniqueModels([model, OLLAMA_MODEL, "qwen2.5-coder:1.5b", "llama3.2:3b", "gemma3:4b"]);
    const errors = [];
    for (const candidate of candidates) {
      try {
        return await completeWithOllama(baseUrl, candidate, system, prompt);
      } catch (error) {
        errors.push(`${candidate}: ${error.message}`);
      }
    }
    throw new Error(`No configured Ollama model could answer. ${errors.join(" | ")}`);
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
  if (!response.ok) throw new Error(`Nex model request failed with HTTP ${response.status}: ${await responseError(response)}`);
  const payload = await response.json();
  if (!payload.choices?.[0]?.message?.content) throw new Error("Nex model returned no content");
  return payload.choices[0].message.content;
}

async function completeWithOllama(baseUrl, model, system, prompt) {
  const response = await fetch(`${baseUrl}/api/chat`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ model, stream: false, messages: [{ role: "system", content: system }, { role: "user", content: prompt }] }),
    signal: AbortSignal.timeout(Number(process.env.OLLAMA_TIMEOUT_MS ?? 120000))
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${await responseError(response)}`);
  const payload = await response.json();
  if (!payload.message?.content) throw new Error("returned no content");
  return payload.message.content;
}

async function responseError(response) {
  const text = await response.text();
  try {
    const payload = JSON.parse(text);
    return payload.error ?? payload.message ?? text;
  } catch {
    return text;
  }
}

function uniqueModels(models) {
  return [...new Set(models.map((candidate) => String(candidate ?? "").trim()).filter(Boolean))];
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
    if (!response.ok) throw new Error(`Ollama could not prepare ${model}: ${await responseError(response)}`);
    return `Prepared ${model} with Ollama`;
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
  const host = process.env.HOST ?? "127.0.0.1";
  createServer().listen(port, host, () => {
    console.log(`Nexus workflow engine listening on http://${host}:${port}`);
    ensureMemoryOnLaunch();
  });
}
