import assert from "node:assert/strict";
import fs from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { buildEchoActions } from "../src/echo-actions.js";
import { executeNode } from "../src/executor.js";
import { NexAssistant } from "../src/assistant/NexAssistant.js";
import { ActionInferrer } from "../src/echo/ActionInferrer.js";
import { configureGenerator, generateNode, getGenerationCount, resetGenerationCount } from "../src/generator.js";
import { createLifePlan } from "../src/life-assistant.js";
import { createMemoryStore } from "../src/memory-store.js";
import { clearServers, registerServer, scrapeServer } from "../src/mcp-registry.js";
import { validateNode, validateSchema } from "../src/node-schema.js";
import { clearNodes, findNode, saveNode } from "../src/node-store.js";
import { PetSpawner } from "../src/pets/PetSpawner.js";
import { configureRunners, resetRunners, RUNNERS } from "../src/runners/index.js";
import { createServer } from "../src/server.js";
import { ActionStore } from "../src/store/ActionStore.js";
import { BRIDGES, createMcpServer, handleJsonRpc } from "../scripts/nexus-mcp-bridge.mjs";
import { loadMcpSecrets, providerAuthStatus, saveProviderSecrets } from "../scripts/mcp-secret-store.mjs";

test.beforeEach(async () => {
  await clearNodes();
  clearServers();
  resetRunners();
  resetGenerationCount();
  configureGenerator({ generate: fixturePlanner });
});

test("generate: intent maps to valid node", async () => {
  const node = await generateNode("open example.com and extract the page title", {});
  assert(node.runner.steps.length > 0);
  assert(node.runner.steps.every((step) => RUNNERS[step.primitive]));
  assert(validateSchema(node));
});

test("generate: invalid model ids are replaced with UUIDs", async () => {
  configureGenerator({ generate: async () => ({
    id: "node-1",
    meta: { app: "browser", category: "web", action: "extract", label: "Extract heading", source: "manual" },
    fields: [
      { id: "url", type: "string", required: true, label: "URL", value: "https://example.com" },
      { id: "selector", type: "string", required: true, label: "Selector", value: "h1" },
      { id: "attribute", type: "string", required: true, label: "Attribute", value: "text" }
    ],
    runner: {
      steps: [
        { primitive: "browser_goto", args: { url: "{{fields.url}}" } },
        { primitive: "browser_extract", args: { selector: "{{fields.selector}}", attribute: "{{fields.attribute}}" } }
      ],
      output_binding: null
    },
    mcp: null
  }) });

  const node = await generateNode("open example.com and extract the page title", {});
  assert.notEqual(node.id, "node-1");
  assert(validateSchema(node));
});

test("generate: bare field bindings are qualified", async () => {
  configureGenerator({ generate: async () => ({
    meta: { app: "files", category: "filesystem", action: "write", label: "Write file", source: "manual" },
    fields: [
      { id: "path", type: "string", required: true, label: "Path", value: "/tmp/nexus-test.txt" },
      { id: "file_content", type: "string", required: true, label: "File content", value: "hello" }
    ],
    runner: {
      steps: [{ primitive: "fs_write", args: { path: "{{path}}", content: "{{file_content}}" } }],
      output_binding: null
    },
    mcp: null
  }) });

  const node = await generateNode("write hello to /tmp/nexus-test.txt", {});
  assert.equal(node.runner.steps[0].args.path, "{{fields.path}}");
  assert.equal(node.runner.steps[0].args.content, "{{fields.file_content}}");
  assert(validateSchema(node));
});

test("generate: unresolved field bindings are rejected and retried", async () => {
  let attempts = 0;
  configureGenerator({ generate: async (_intent, _context, correction) => {
    attempts += 1;
    const content = correction ? "final nexus smoke" : "{{intent}}";
    return {
      meta: { app: "files", category: "filesystem", action: "write", label: "Write file", source: "manual" },
      fields: [
        { id: "path", type: "string", required: true, label: "Path", value: "/tmp/nexus-retry-test.txt" },
        { id: "content", type: "string", required: true, label: "Content", value: content }
      ],
      runner: {
        steps: [{ primitive: "fs_write", args: { path: "{{path}}", content: "{{content}}" } }],
        output_binding: null
      },
      mcp: null
    };
  } });

  const node = await generateNode("write final nexus smoke to /tmp/nexus-retry-test.txt", {});
  assert.equal(attempts, 2);
  assert.equal(node.fields.find((field) => field.id === "content").value, "final nexus smoke");
  assert(validateSchema(node));
});

test("generate: deterministic fallback handles literal file writes", async () => {
  configureGenerator({ generate: async () => ({
    meta: { app: "files", category: "filesystem", action: "write", label: "Write file", source: "manual" },
    fields: [
      { id: "path", type: "string", required: true, label: "Path", value: "/tmp/nexus-fallback-test.txt" },
      { id: "content", type: "string", required: true, label: "Content", value: "{{intent}}" }
    ],
    runner: {
      steps: [{ primitive: "fs_write", args: { path: "{{fields.path}}", content: "{{fields.content}}" } }],
      output_binding: null
    },
    mcp: null
  }) });

  const node = await generateNode("write final nexus smoke to /tmp/nexus-fallback-test.txt", {});
  assert.equal(node.fields.find((field) => field.id === "path").value, "/tmp/nexus-fallback-test.txt");
  assert.equal(node.fields.find((field) => field.id === "content").value, "final nexus smoke");
  assert(validateSchema(node));
});

test("generate: unmappable intent returns error object", async () => {
  const result = await generateNode("make me a coffee", {});
  assert.equal(result.error, "cannot_map");
});

test("store: saved node returned for similar intent", async () => {
  const node = await generateNode("send an http post to a webhook", {});
  await saveNode(node, "send an http post to a webhook");
  const found = await findNode("post data to a webhook url");
  assert(found);
  assert.equal(found.id, node.id);
});

test("execute: browser_goto + browser_extract returns real data", async () => {
  configureRunners({ browser: {
    goto: async () => {},
    extract: async () => "Example Domain"
  } });
  const node = await generateNode("go to example.com and extract the h1 text", {});
  const result = await executeNode(node, {});
  assert.equal(result.output, "Example Domain");
});

test("execute: no AI calls during execution", async () => {
  let aiCalled = false;
  configureRunners({ ai: { infer: async () => { aiCalled = true; } } });
  await fs.writeFile("/tmp/nexus-test.txt", "hello", "utf8");
  const node = await generateNode("read file at /tmp/nexus-test.txt", {});
  const result = await executeNode(node, {});
  assert.equal(result.output, "hello");
  assert.equal(aiCalled, false);
});

test("mcp: register server produces valid nodes", async () => {
  const server = http.createServer((request, response) => {
    response.setHeader("content-type", "application/json");
    response.end(JSON.stringify({ jsonrpc: "2.0", id: "1", result: { tools: [{
      name: "echo",
      description: "Echo input",
      inputSchema: { type: "object", properties: { text: { type: "string" } }, required: ["text"] }
    }] } }));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    await registerServer("test", `http://127.0.0.1:${port}`);
    const nodes = await scrapeServer("test");
    assert(nodes.length > 0);
    assert(nodes.every((node) => validateSchema(node)));
    assert(nodes.every((node) => node.mcp !== null));
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("mcp bridge: exposes provider tools and reports auth setup gaps", async () => {
  for (const app of Object.keys(BRIDGES)) {
    const payload = await handleJsonRpc(app, { jsonrpc: "2.0", id: app, method: "tools/list", params: {} }, {});
    assert.equal(payload.result.tools.length, BRIDGES[app].tools.length);
    assert(payload.result.tools.every((tool) => tool.inputSchema?.type === "object"));
  }

  await assert.rejects(
    () => handleJsonRpc("gmail", {
      jsonrpc: "2.0",
      id: "gmail",
      method: "tools/call",
      params: { name: "draft_email", arguments: { subject: "Follow-up", body: "hello" } }
    }, {}),
    /Google needs GOOGLE_CLIENT_ID/
  );

  const slack = await handleJsonRpc("slack", {
    jsonrpc: "2.0",
    id: "slack",
    method: "tools/call",
    params: { name: "draft_message", arguments: { channel: "#general", message: "hello" } }
  }, {});
  assert.equal(slack.result.preview, true);
  assert.equal(slack.result.readOnly, true);
  assert.equal(slack.result.channel, "#general");

  await assert.rejects(
    () => handleJsonRpc("slack", {
      jsonrpc: "2.0",
      id: "slack-search",
      method: "tools/call",
      params: { name: "search_messages", arguments: { query: "nexus" } }
    }, {}),
    /Slack read access needs/
  );

  await assert.rejects(
    () => handleJsonRpc("notion", {
      jsonrpc: "2.0",
      id: "notion",
      method: "tools/call",
      params: { name: "create_tasks", arguments: { title: "Tasks", tasks: "- Ship Nexus" } }
    }, {}),
    /Notion needs NOTION_TOKEN/
  );
});

test("mcp secrets: save and merge ignored local provider auth", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "nexus-mcp-secrets-"));
  const env = { NEXUS_MCP_SECRET_DIR: dir };
  try {
    await saveProviderSecrets("google", { clientId: "google-client", clientSecret: "google-secret" }, env);
    await saveProviderSecrets("google", { refreshToken: "google-refresh" }, env);
    await saveProviderSecrets("slack", { userToken: "xoxp-read" }, env);
    await saveProviderSecrets("notion", { token: "notion-token", parentPageId: "page-id" }, env);

    const secrets = await loadMcpSecrets(env);
    assert.equal(secrets.google.clientId, "google-client");
    assert.equal(secrets.google.clientSecret, "google-secret");
    assert.equal(secrets.google.refreshToken, "google-refresh");
    assert.equal(secrets.slack.userToken, "xoxp-read");
    assert.equal(secrets.notion.parentPageId, "page-id");

    const status = await providerAuthStatus(env);
    assert.equal(status.google.ok, true);
    assert.equal(status.slack.ok, true);
    assert.equal(status.slack.readOnly, true);
    assert.equal(status.notion.ok, true);
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
});

test("mcp bridge: file-backed secrets drive real provider API calls", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "nexus-mcp-real-"));
  const env = { NEXUS_MCP_SECRET_DIR: dir };
  const calls = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, options = {}) => {
    calls.push({ url: String(url), options });
    const href = String(url);
    if (href.includes("gmail.googleapis.com")) return jsonResponse({ id: "draft-1", message: { id: "message-1" } });
    if (href.includes("calendar/v3")) return jsonResponse({ id: "event-1", htmlLink: "https://calendar.example/event-1" });
    if (href.includes("docs.googleapis.com/v1/documents/") && href.includes(":batchUpdate")) return jsonResponse({});
    if (href.includes("docs.googleapis.com/v1/documents")) return jsonResponse({ documentId: "doc-1" });
    if (href.includes("slack.com/api/conversations.list")) return jsonResponse({ ok: true, channels: [{ id: "C1", name: "general" }] });
    if (href.includes("slack.com/api/search.messages")) return jsonResponse({ ok: true, messages: { total: 1, matches: [{ text: "nexus", ts: "1.0", channel: { id: "C1", name: "general" } }] } });
    if (href.includes("api.notion.com/v1/pages")) return jsonResponse({ id: "page-1", url: "https://notion.example/page-1" });
    return jsonResponse({ ok: true });
  };
  try {
    await saveProviderSecrets("google", { accessToken: "google-token" }, env);
    await saveProviderSecrets("slack", { userToken: "slack-token" }, env);
    await saveProviderSecrets("notion", { token: "notion-token", parentPageId: "page-id" }, env);

    const gmail = await handleJsonRpc("gmail", {
      jsonrpc: "2.0",
      id: "gmail",
      method: "tools/call",
      params: { name: "draft_email", arguments: { subject: "Follow-up", body: "hello" } }
    }, env);
    assert.equal(gmail.result.draftId, "draft-1");

    const calendar = await handleJsonRpc("google-workspace", {
      jsonrpc: "2.0",
      id: "calendar",
      method: "tools/call",
      params: { name: "create_calendar_event", arguments: { title: "Sync", start: "2026-06-08T09:00:00", end: "2026-06-08T09:30:00" } }
    }, env);
    assert.equal(calendar.result.eventId, "event-1");

    const doc = await handleJsonRpc("google-drive", {
      jsonrpc: "2.0",
      id: "doc",
      method: "tools/call",
      params: { name: "create_doc", arguments: { name: "Notes", body: "hello" } }
    }, env);
    assert.equal(doc.result.documentId, "doc-1");

    const slackList = await handleJsonRpc("slack", {
      jsonrpc: "2.0",
      id: "slack-list",
      method: "tools/call",
      params: { name: "list_channels", arguments: { limit: 1 } }
    }, env);
    assert.equal(slackList.result.channels[0].name, "general");
    assert.equal(slackList.result.readOnly, true);

    const slackSearch = await handleJsonRpc("slack", {
      jsonrpc: "2.0",
      id: "slack-search",
      method: "tools/call",
      params: { name: "search_messages", arguments: { query: "nexus" } }
    }, env);
    assert.equal(slackSearch.result.total, 1);

    const notion = await handleJsonRpc("notion", {
      jsonrpc: "2.0",
      id: "notion",
      method: "tools/call",
      params: { name: "create_tasks", arguments: { title: "Tasks", tasks: "- Ship Nexus" } }
    }, env);
    assert.equal(notion.result.pageId, "page-1");

    assert(calls.some((call) => call.url.includes("gmail.googleapis.com/gmail/v1/users/me/drafts")));
    assert(calls.some((call) => call.url.includes("slack.com/api/search.messages")));
    assert(calls.every((call) => !call.url.includes("chat.postMessage")));
  } finally {
    globalThis.fetch = originalFetch;
    await fs.rm(dir, { recursive: true, force: true });
  }
});

test("mcp connect: oauth URL and callback save verified provider tokens", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "nexus-mcp-connect-"));
  const env = { NEXUS_MCP_SECRET_DIR: dir };
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, options = {}) => {
    const href = String(url);
    if (href.includes("oauth2.googleapis.com/tokeninfo")) return jsonResponse({ scope: [
      "https://www.googleapis.com/auth/gmail.compose",
      "https://www.googleapis.com/auth/calendar.events",
      "https://www.googleapis.com/auth/documents"
    ].join(" ") });
    if (href.includes("oauth2.googleapis.com/token")) return jsonResponse({ access_token: "google-access", refresh_token: "google-refresh" });
    if (href.includes("slack.com/api/oauth.v2.access")) return jsonResponse({ ok: true, authed_user: { access_token: "xoxp-read" }, team: { id: "T1" } });
    if (href.includes("slack.com/api/auth.test")) return jsonResponse({ ok: true, team_id: "T1" });
    if (href.includes("api.notion.com/v1/oauth/token")) return jsonResponse({ access_token: "secret_notion", workspace_id: "W1", bot_id: "B1" });
    if (href.includes("api.notion.com/v1/users/me")) return jsonResponse({ object: "user", id: "notion-bot" });
    return jsonResponse({ ok: true });
  };
  try {
    await saveProviderSecrets("google", { clientId: "google-client", clientSecret: "google-secret" }, env);
    await saveProviderSecrets("slack", { clientId: "slack-client", clientSecret: "slack-secret" }, env);
    await saveProviderSecrets("notion", { clientId: "notion-client", clientSecret: "notion-secret", parentPageId: "page-id" }, env);

    await runConnectCallbackSmoke("gmail", env, /accounts\.google\.com/, originalFetch);
    await runConnectCallbackSmoke("slack", env, /slack\.com\/oauth\/v2\/authorize/, originalFetch);
    await runConnectCallbackSmoke("notion", env, /api\.notion\.com\/v1\/oauth\/authorize/, originalFetch);

    const status = await providerAuthStatus(env);
    assert.equal(status.google.connected, true);
    assert.equal(status.slack.connected, true);
    assert.equal(status.notion.connected, true);
  } finally {
    globalThis.fetch = originalFetch;
    await fs.rm(dir, { recursive: true, force: true });
  }
});

test("workflow: node output binds to next node input", async () => {
  configureRunners({ browser: {
    goto: async () => {},
    extract: async () => "$12.34"
  } });
  const n1 = await generateNode("extract the price from {{trigger.url}}", {});
  const n2 = await generateNode("write a string to /tmp/nexus-result.txt", {});
  n2.fields.find((field) => field.id === "content").value = "{{nodes.0.output}}";
  const context = { trigger: { url: "https://example.com" } };
  const r1 = await executeNode(n1, context);
  await executeNode(n2, { ...context, nodes: { 0: r1 } });
  assert.equal(await fs.readFile("/tmp/nexus-result.txt", "utf8"), "$12.34");
});

test("store: reused node skips generation", async () => {
  await generateNode("send a get request to a url", {});
  await generateNode("send a get request to a url", {});
  assert.equal(getGenerationCount(), 1);
});

test("schema: unknown primitive is rejected before execution", () => {
  assert.throws(() => validateNode({
    id: crypto.randomUUID(),
    meta: { app: "x", category: "x", action: "x", label: "x", source: "manual" },
    fields: [],
    runner: { steps: [{ primitive: "unknown", args: {} }], output_binding: null },
    mcp: null
  }), /unknown primitive/);
});

test("api: generated nodes are returned from the local server", async () => {
  const server = createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    const response = await fetch(`http://127.0.0.1:${port}/node/generate`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ intent: "open example.com and extract the page title", context: {} })
    });
    const node = await response.json();
    assert.equal(response.status, 200);
    assert(validateSchema(node));
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("api: health advertises echo action compatibility", async () => {
  const server = createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    const response = await fetch(`http://127.0.0.1:${port}/health`);
    const payload = await response.json();
    assert.equal(response.status, 200);
    assert.equal(payload.features.echoActions, true);
    assert.equal(payload.features.echoMCPWorkflows, true);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("echo: live chunks infer ambiguous meeting actions before recording stops", async () => {
  const store = new ActionStore();
  const inferrer = new ActionInferrer({ store, intervalWords: 5, confidenceThreshold: 0.7 });
  const sessionId = "meeting-live";
  await inferrer.handleChunk({ sessionId, title: "Marcus sync", text: "okay let's book a 3pm tomorrow with Marcus" });
  await inferrer.handleChunk({ sessionId, title: "Marcus sync", text: "and put the design action items into Notion" });
  const actions = store.snapshot(sessionId).actions;
  assert(actions.some((action) => action.tool === "calendar_create_event"));
  assert(actions.some((action) => action.tool === "notion_create_page"));
  assert(actions.find((action) => action.tool === "calendar_create_event").params.when.includes("3pm"));
});

test("echo: duplicate source quotes are not emitted twice", async () => {
  const store = new ActionStore();
  const inferrer = new ActionInferrer({ store, intervalWords: 1, confidenceThreshold: 0.7 });
  const sessionId = "meeting-dedupe";
  const text = "let's schedule a meeting tomorrow at 3pm with Marcus";
  await inferrer.handleChunk({ sessionId, text });
  await inferrer.handleChunk({ sessionId, text });
  const calendarActions = store.snapshot(sessionId).actions.filter((action) => action.tool === "calendar_create_event");
  assert.equal(calendarActions.length, 1);
});

test("echo: semantically duplicate MCP actions collapse even when quotes drift", () => {
  const store = new ActionStore();
  store.upsertAction({
    type: "mcp_action",
    tool: "gmail_draft_email",
    params: { subject: "QA Report", to: "Steve", body: "Draft QA report follow-up" },
    confidence: 0.82,
    source_quote: "draft an email to Steve about the QA report"
  }, { sessionId: "meeting-semantic-dedupe" });
  store.upsertAction({
    type: "mcp_action",
    tool: "gmail_draft_email",
    params: { subject: "QA Report", to: "Steve", body: "Draft QA report follow-up" },
    confidence: 0.81,
    source_quote: "please draft an email to Steve about the QA report for Q1"
  }, { sessionId: "meeting-semantic-dedupe" });
  assert.equal(store.snapshot("meeting-semantic-dedupe").actions.length, 1);
});

test("echo: keyword mentions alone do not infer MCP actions", async () => {
  const store = new ActionStore();
  const inferrer = new ActionInferrer({ store, intervalWords: 1, confidenceThreshold: 0.7 });
  const sessionId = "meeting-keyword-only";
  await inferrer.handleChunk({ sessionId, text: "Gmail Notion calendar drive notes action items engineering design" });
  assert.equal(store.snapshot(sessionId).actions.length, 0);
});

test("echo: pet spawner updates action lifecycle independently", async () => {
  const store = new ActionStore();
  const spawner = new PetSpawner({ store });
  const action = store.upsertAction({
    type: "mcp_action",
    tool: "calendar_create_event",
    params: { title: "Marcus sync", when: "tomorrow 3pm" },
    confidence: 0.9,
    source_quote: "book a 3pm tomorrow with Marcus"
  }, { sessionId: "meeting-pet" });
  spawner.spawn(action);
  await new Promise((resolve) => setTimeout(resolve, 50));
  const updated = store.snapshot("meeting-pet").actions[0];
  assert.equal(updated.status, "done");
  assert.equal(updated.result.ok, true);
});

test("echo: assistant edits, splits, and cancels queue actions", async () => {
  const store = new ActionStore();
  const spawner = new PetSpawner({ store });
  const assistant = new NexAssistant({ store, spawner });
  const sessionId = "meeting-assistant";
  store.upsertAction({
    type: "mcp_action",
    tool: "calendar_create_event",
    params: { title: "Marcus sync", when: "tomorrow 3pm" },
    confidence: 0.9,
    source_quote: "book a 3pm tomorrow with Marcus"
  }, { sessionId });
  store.upsertAction({
    type: "mcp_action",
    tool: "notion_create_page",
    params: { title: "Meeting notes", content: "Design needs mockups. Engineering needs API owners." },
    confidence: 0.84,
    source_quote: "put the notes in notion"
  }, { sessionId });
  const email = store.upsertAction({
    type: "mcp_action",
    tool: "gmail_draft_email",
    params: { subject: "Follow up", body: "Meeting recap" },
    confidence: 0.8,
    source_quote: "send that email"
  }, { sessionId });
  await assistant.handleMessage({ sessionId, message: "change that calendar event to 4pm not 3pm" });
  assert(store.snapshot(sessionId).actions.some((action) => action.tool === "calendar_create_event" && action.params.when.includes("4pm")));
  await assistant.handleMessage({ sessionId, message: "actually split that into two notion pages, one for design and one for eng" });
  assert.equal(store.snapshot(sessionId).actions.filter((action) => action.tool === "notion_create_page").length, 2);
  await assistant.handleMessage({ sessionId, message: "don't send that email" });
  assert.equal(store.snapshot(sessionId).actions.find((action) => action.id === email.id).status, "canceled");
});

test("life: pasted meeting notes produce a command plan", () => {
  const plan = createLifePlan(`Meeting title: Class officer planning
Date: 2026-06-01

Context:
Plan homecoming prep, committee assignments, and follow-up logistics.

Resources:
Signup sheet: https://example.com/signup

Questions:
Who owns the final decoration budget?

Due dates:
Finish the signup cleanup by tomorrow

Next meeting:
June 3, 2026 at 4:30 PM

Meeting minutes:
I need to send the committee recap by tomorrow.
Prepare the homecoming task list before Friday.`);

  assert.equal(plan.title, "Class officer planning");
  assert.equal(plan.stats.tasks, 3);
  assert.equal(plan.resources[0].url, "https://example.com/signup");
  assert(plan.questions.some((question) => question.text.includes("decoration budget")));
  assert.equal(plan.nextMeeting.dateText, "June 3, 2026");
  assert(plan.automations[0].intent.includes("write a string"));
  assert(plan.automations.some((automation) => automation.id === "automation-calendar-draft"));
  assert(plan.automations.some((automation) => automation.id === "automation-gmail-draft"));
  assert(plan.automations.some((automation) => automation.id === "automation-open-resource"));
  assert(plan.warnings.some((warning) => warning.includes("dry run")));
});

test("life: transcript paste ignores template noise and keeps follow-up actions", () => {
  const plan = createLifePlan(`NOTICE OF MEETING
Meeting transcript:
Minutes recorder: Rushil
Present: Class officers
\u2022 Alex - reviewed decoration ideas
\u2022 I need to send the sponsor recap by tonight.
\u2022 Question: Who approves the room request?
\u2022 Next meeting is June 5, 2026 at 4:00 PM.
____
(please review meeting minutes)`);

  assert.equal(plan.title, "Life command plan");
  assert.equal(plan.tasks.length, 1);
  assert.equal(plan.tasks[0].title, "send the sponsor recap");
  assert.equal(plan.tasks[0].priority, "high");
  assert(plan.questions.some((question) => question.text.includes("room request")));
  assert.equal(plan.nextMeeting.dateText, "June 5, 2026");
  assert.equal(plan.nextMeeting.timeText, "4:00 PM");
});

test("api: life plan endpoint returns suggested automations", async () => {
  const server = createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    const response = await fetch(`http://127.0.0.1:${port}/life/plan`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ text: "Title: Weekly reset\nTasks:\n- Review calendar by tonight\nQuestions:\nWhat should move to next week?" })
    });
    const plan = await response.json();
    assert.equal(response.status, 200);
    assert.equal(plan.title, "Weekly reset");
    assert.equal(plan.stats.tasks, 1);
    assert(plan.automations.length >= 1);
    assert.equal(plan.automations[0].requiresApproval, true);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("api: echo actions infer MCP follow-ups from meeting context", async () => {
  const server = createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    const response = await fetch(`http://127.0.0.1:${port}/echo/actions`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        title: "Weekly customer sync",
        transcript: "We need to send a follow-up email, notify the Slack channel, create Notion tasks, write a recap doc, and schedule the next meeting.",
        notes: ""
      })
    });
    const payload = await response.json();
    assert.equal(response.status, 200);
    assert(payload.actions.some((action) => action.provider === "Gmail" && action.mcp.tool === "draft_email"));
    assert(payload.actions.some((action) => action.provider === "Slack"));
    assert(payload.actions.some((action) => action.provider === "Notion"));
    assert(payload.actions.some((action) => action.provider === "Google Drive"));
    assert(payload.actions.some((action) => action.provider === "Google Workspace"));
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("api: echo actions build multi-step invite workflow from natural speech", async () => {
  const server = createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    const response = await fetch(`http://127.0.0.1:${port}/echo/actions`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        title: "Untitled Echo",
        transcript: "Yeah Stephen so I was thinking tomorrow why don't we sync up again. You just shoot me over an invite and we'll figure it out from there.",
        notes: "Meeting Notes: Follow-up Discussion"
      })
    });
    const payload = await response.json();
    assert.equal(response.status, 200);
    const workflow = payload.actions.find((action) => action.kind === "meeting_followup_workflow");
    assert(workflow, "expected a multi-step MCP workflow");
    assert.equal(workflow.provider, "MCP Workflow");
    assert.equal(workflow.mcp.steps.length, 2);
    assert(workflow.mcp.steps.some((step) => step.server === "google-workspace" && step.tool === "create_calendar_event"));
    assert(workflow.mcp.steps.some((step) => step.server === "gmail" && step.tool === "draft_email"));
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("api: echo actions build invite workflows without screenshot-specific wording", async () => {
  const server = createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    const response = await fetch(`http://127.0.0.1:${port}/echo/actions`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        title: "Product sync",
        transcript: "Maya wants us to meet again on Friday. Draft the invite and follow up with the decisions from the call.",
        notes: "Next step: schedule follow up. Owner: Maya."
      })
    });
    const payload = await response.json();
    assert.equal(response.status, 200);
    const workflow = payload.actions.find((action) => action.kind === "meeting_followup_workflow");
    assert(workflow, "expected a multi-step MCP workflow");
    const calendarStep = workflow.mcp.steps.find((step) => step.server === "google-workspace");
    const emailStep = workflow.mcp.steps.find((step) => step.server === "gmail");
    assert(calendarStep, "expected a Google Workspace calendar step");
    assert(emailStep, "expected a Gmail draft step");
    assert.equal(calendarStep.inputs.when_hint, "Friday");
    assert.equal(calendarStep.inputs.attendees_hint, "Maya");
    assert.equal(emailStep.inputs.to_hint, "Maya");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("echo: memory context does not become attendees or action triggers", () => {
  const actions = buildEchoActions({
    title: "Product sync",
    transcript: "Maya wants us to meet again on Friday. Draft the invite and follow up with the decisions from the call.",
    notes: "Next step: schedule follow up. Owner: Maya.",
    memory: "Created Nexus brief. Personal assistant priority. Stephen asked for an unrelated invite."
  });

  const workflow = actions.find((action) => action.kind === "meeting_followup_workflow");
  assert(workflow, "expected a multi-step MCP workflow");
  const calendarStep = workflow.mcp.steps.find((step) => step.server === "google-workspace");
  const emailStep = workflow.mcp.steps.find((step) => step.server === "gmail");
  assert.equal(calendarStep.inputs.attendees_hint, "Maya");
  assert.equal(emailStep.inputs.to_hint, "Maya");

  const followUpActions = buildEchoActions({
    title: "Weekly customer sync",
    transcript: "We need to send a follow-up email, notify the Slack channel, create Notion tasks, write a recap doc, and schedule the next meeting.",
    memory: "Old memory says shoot me over an invite."
  });

  assert(followUpActions.some((action) => action.provider === "Gmail" && action.mcp.tool === "draft_email"));
  assert.equal(followUpActions.some((action) => action.kind === "meeting_followup_workflow"), false);
});

test("echo: provider names do not become invite attendees", () => {
  const actions = buildEchoActions({
    title: "Integration smoke",
    transcript: "Maya wants us to meet again on Friday. Draft the invite, send a follow-up email, notify Slack, create Notion tasks, and write a recap doc.",
    notes: "Owner: Maya. Next step: schedule follow up."
  });
  const workflow = actions.find((action) => action.kind === "meeting_followup_workflow");
  assert(workflow, "expected a multi-step MCP workflow");
  const calendarStep = workflow.mcp.steps.find((step) => step.server === "google-workspace");
  const emailStep = workflow.mcp.steps.find((step) => step.server === "gmail");
  assert.equal(calendarStep.inputs.attendees_hint, "Maya");
  assert.equal(emailStep.inputs.to_hint, "Maya");
});

test("echo: title words do not become invite attendees", () => {
  const actions = buildEchoActions({
    title: "Pull retest",
    transcript: "Maya wants us to meet again on Friday. Draft the invite and follow up with the decisions from the call.",
    notes: "Next step: schedule follow up. Owner: Maya."
  });
  const workflow = actions.find((action) => action.kind === "meeting_followup_workflow");
  assert(workflow, "expected a multi-step MCP workflow");
  const calendarStep = workflow.mcp.steps.find((step) => step.server === "google-workspace");
  const emailStep = workflow.mcp.steps.find((step) => step.server === "gmail");
  assert.equal(calendarStep.inputs.attendees_hint, "Maya");
  assert.equal(emailStep.inputs.to_hint, "Maya");
});

test("api: echo action run reports missing MCP registration", async () => {
  const server = createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    const action = {
      id: crypto.randomUUID(),
      kind: "email_follow_up",
      provider: "Gmail",
      title: "Draft follow-up email",
      summary: "Prepare email",
      confidence: 0.8,
      status: "suggested",
      mcp: { server: "gmail", tool: "draft_email", inputs: { body: "hello" } }
    };
    const response = await fetch(`http://127.0.0.1:${port}/echo/action/run`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ action })
    });
    const payload = await response.json();
    assert.equal(response.status, 200);
    assert.equal(payload.ok, false);
    assert.equal(payload.status, "needs_mcp");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("api: echo action run executes registered MCP tool", async () => {
  const calls = [];
  const mcpServer = http.createServer((request, response) => {
    let body = "";
    request.on("data", (chunk) => {
      body += chunk;
    });
    request.on("end", () => {
      const payload = JSON.parse(body || "{}");
      response.setHeader("content-type", "application/json");
      if (payload.method === "tools/list") {
        response.end(JSON.stringify({
          jsonrpc: "2.0",
          id: payload.id,
          result: {
            tools: [{
              name: "draft_email",
              description: "Draft email",
              inputSchema: {
                type: "object",
                properties: { body: { type: "string" } },
                required: ["body"]
              }
            }]
          }
        }));
        return;
      }
      calls.push(payload.params);
      response.end(JSON.stringify({
        jsonrpc: "2.0",
        id: payload.id,
        result: { ok: true, draftId: "draft-1" }
      }));
    });
  });
  await new Promise((resolve) => mcpServer.listen(0, "127.0.0.1", resolve));

  const server = createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  const mcpPort = mcpServer.address().port;
  try {
    await fetch(`http://127.0.0.1:${port}/mcp/register`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ app: "gmail", url: `http://127.0.0.1:${mcpPort}` })
    });
    const action = {
      id: crypto.randomUUID(),
      kind: "email_follow_up",
      provider: "Gmail",
      title: "Draft follow-up email",
      summary: "Prepare email",
      confidence: 0.8,
      status: "suggested",
      mcp: { server: "gmail", tool: "draft_email", inputs: { body: "hello" } }
    };
    const response = await fetch(`http://127.0.0.1:${port}/echo/action/run`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ action })
    });
    const payload = await response.json();
    assert.equal(response.status, 200);
    assert.equal(payload.status, "executed");
    assert.equal(payload.results[0].result.draftId, "draft-1");
    assert.equal(calls[0].name, "draft_email");
    assert.equal(calls[0].arguments.body, "hello");
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await new Promise((resolve) => mcpServer.close(resolve));
  }
});

test("api: Nex completion uses and updates local memory", async () => {
  const qdrant = await startFakeQdrant();
  let receivedMessages = [];
  const model = http.createServer(async (request, response) => {
    const body = await readJsonBody(request);
    receivedMessages = body.messages ?? [];
    sendJson(response, 200, { message: { content: "Use the local-first preference." } });
  });
  await new Promise((resolve) => model.listen(0, "127.0.0.1", resolve));
  const modelPort = model.address().port;
  const previous = {
    qdrant: process.env.NEXUS_QDRANT_URL,
    collection: process.env.NEXUS_MEMORY_COLLECTION,
    ollama: process.env.OLLAMA_BASE_URL
  };
  process.env.NEXUS_QDRANT_URL = qdrant.url;
  process.env.NEXUS_MEMORY_COLLECTION = "assistant_memories";
  process.env.OLLAMA_BASE_URL = `http://127.0.0.1:${modelPort}`;

  const server = createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    const store = createMemoryStore({ url: qdrant.url, collectionName: "assistant_memories", vectorSize: 384 });
    await store.remember({
      memory_type: "user_preference",
      content: "The user prefers local-first assistant behavior.",
      source: "qa",
      importance: 0.95,
      project: "nexus",
      tags: ["assistant", "privacy"]
    });

    const response = await fetch(`http://127.0.0.1:${port}/nex/complete`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ prompt: "What assistant behavior do I prefer?", brain: { provider: "ollama", model: "test-model", baseUrl: `http://127.0.0.1:${modelPort}` } })
    });
    const payload = await response.json();

    assert.equal(response.status, 200);
    assert.equal(payload.completion, "Use the local-first preference.");
    assert(receivedMessages[0].content.includes("The user prefers local-first assistant behavior."));
    assert.equal(qdrant.state.pointsFor("assistant_memories").size, 3);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await new Promise((resolve) => model.close(resolve));
    await qdrant.stop();
    restoreEnv("NEXUS_QDRANT_URL", previous.qdrant);
    restoreEnv("NEXUS_MEMORY_COLLECTION", previous.collection);
    restoreEnv("OLLAMA_BASE_URL", previous.ollama);
  }
});

test("api: Nex completion accepts long transcript payloads", async () => {
  let receivedPrompt = "";
  const model = http.createServer(async (request, response) => {
    const body = await readJsonBody(request);
    receivedPrompt = body.messages?.[1]?.content ?? "";
    sendJson(response, 200, { message: { content: "Long transcript accepted." } });
  });
  await new Promise((resolve) => model.listen(0, "127.0.0.1", resolve));
  const modelPort = model.address().port;
  const previous = {
    memoryEnabled: process.env.NEXUS_MEMORY_ENABLED,
    ollama: process.env.OLLAMA_BASE_URL
  };
  process.env.NEXUS_MEMORY_ENABLED = "0";
  process.env.OLLAMA_BASE_URL = `http://127.0.0.1:${modelPort}`;

  const server = createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  const prompt = `Meeting transcript:\n${"Nex should handle long pasted transcript payloads. ".repeat(3600)}`;
  try {
    const response = await fetch(`http://127.0.0.1:${port}/nex/complete`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ prompt, brain: { provider: "ollama", model: "test-model", baseUrl: `http://127.0.0.1:${modelPort}` } })
    });
    const payload = await response.json();

    assert.equal(response.status, 200);
    assert.equal(payload.completion, "Long transcript accepted.");
    assert.equal(receivedPrompt, prompt);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await new Promise((resolve) => model.close(resolve));
    restoreEnv("NEXUS_MEMORY_ENABLED", previous.memoryEnabled);
    restoreEnv("OLLAMA_BASE_URL", previous.ollama);
  }
});

test("memory: ensures local qdrant collection and payload indexes", async () => {
  const qdrant = await startFakeQdrant();
  try {
    const store = createMemoryStore({ url: qdrant.url, collectionName: "test_memories", vectorSize: 32 });
    const result = await store.ensureCollection();

    assert.equal(result.ok, true);
    assert.equal(result.created, true);
    assert.equal(qdrant.state.collections.has("test_memories"), true);
    assert(qdrant.state.indexes.some((index) => index.collection === "test_memories" && index.field_name === "memory_type"));
    assert(qdrant.state.indexes.some((index) => index.collection === "test_memories" && index.field_name === "content_hash"));
  } finally {
    await qdrant.stop();
  }
});

test("memory: stores payload metadata, deduplicates, and ranks query results", async () => {
  const qdrant = await startFakeQdrant();
  try {
    const store = createMemoryStore({ url: qdrant.url, collectionName: "test_memories", vectorSize: 32 });
    const saved = await store.remember({
      memory_type: "user_preference",
      content: "Rushil wants Nexus memory to stay local in qdrant_storage.",
      timestamp: "2026-06-02T10:00:00.000Z",
      source: "qa",
      importance: 0.95,
      project: "nexus",
      tags: ["privacy", "qdrant"]
    });
    const duplicate = await store.remember({
      memory_type: "user_preference",
      content: "Rushil wants Nexus memory to stay local in qdrant_storage.",
      timestamp: "2026-06-02T10:00:00.000Z",
      source: "qa",
      importance: 0.95,
      project: "nexus",
      tags: ["privacy", "qdrant"]
    });
    await store.remember({
      memory_type: "workflow",
      content: "Nexus can draft calendar followups from pasted meeting notes.",
      timestamp: "2026-05-02T10:00:00.000Z",
      source: "life/plan",
      importance: 0.4,
      project: "nexus",
      tags: ["workflow"]
    });

    assert.equal(saved.duplicate, false);
    assert.equal(duplicate.duplicate, true);
    assert.equal(qdrant.state.pointsFor("test_memories").size, 2);
    for (const field of ["memory_type", "content", "timestamp", "source", "importance", "project", "tags"]) {
      assert(Object.hasOwn(saved.payload, field));
    }

    const result = await store.query("private local qdrant storage memory", {
      project: "nexus",
      limit: 2,
      now: new Date("2026-06-02T12:00:00.000Z")
    });

    assert.equal(result.ok, true);
    assert.equal(result.memories.length, 2);
    assert.equal(result.memories[0].payload.memory_type, "user_preference");
    assert(result.memories[0].rank >= result.memories[1].rank);
  } finally {
    await qdrant.stop();
  }
});

function fixturePlanner(intent) {
  const lower = intent.toLowerCase();
  if (lower.includes("coffee")) return { error: "cannot_map", reason: "No physical runner exists" };
  if (lower.includes("extract") || lower.includes("title") || lower.includes("h1")) {
    return fixtureNode({
      action: "extract_data",
      fields: [
        fixtureField("url", lower.includes("{{trigger.url}}") ? "{{trigger.url}}" : "https://example.com"),
        fixtureField("selector", lower.includes("title") ? "title" : "h1"),
        fixtureField("output", lower.includes("title") ? "title" : "result", false)
      ],
      steps: [
        { primitive: "browser_goto", args: { url: "{{fields.url}}" } },
        { primitive: "browser_extract", args: { selector: "{{fields.selector}}", attribute: "innerText" } }
      ],
      output_binding: "{{fields.output}}"
    });
  }
  if (lower.includes("write")) {
    return fixtureNode({
      action: "write_file",
      fields: [fixtureField("path", "/tmp/nexus-result.txt"), fixtureField("content", "fixture content")],
      steps: [{ primitive: "fs_write", args: { path: "{{fields.path}}", content: "{{fields.content}}" } }]
    });
  }
  if (lower.includes("read file")) {
    return fixtureNode({
      action: "read_file",
      fields: [fixtureField("path", "/tmp/nexus-test.txt")],
      steps: [{ primitive: "fs_read", args: { path: "{{fields.path}}" } }]
    });
  }
  return fixtureNode({
    action: "http_request",
    fields: [fixtureField("url", "https://example.com"), fixtureField("method", lower.includes("post") ? "POST" : "GET")],
    steps: [{ primitive: "http_request", args: { url: "{{fields.url}}", method: "{{fields.method}}" } }]
  });
}

function fixtureNode({ action, fields, steps, output_binding = null }) {
  return {
    id: crypto.randomUUID(),
    meta: { app: "fixture", category: "test", action, label: action, source: "manual" },
    fields,
    runner: { steps, output_binding },
    mcp: null
  };
}

function fixtureField(id, value, required = true) {
  return { id, type: "string", required, label: id, value };
}

async function startFakeQdrant() {
  const collections = new Set();
  const pointsByCollection = new Map();
  const indexes = [];

  const server = http.createServer(async (request, response) => {
    const url = new URL(request.url, "http://127.0.0.1");
    const pathname = url.pathname;
    const body = await readJsonBody(request);
    if (request.method === "GET" && pathname === "/") {
      return sendJson(response, 200, { title: "fake qdrant" });
    }

    const collectionMatch = pathname.match(/^\/collections\/([^/]+)$/);
    if (collectionMatch) {
      const collection = decodeURIComponent(collectionMatch[1]);
      if (request.method === "GET") {
        if (!collections.has(collection)) return sendJson(response, 404, { status: { error: "not found" } });
        return sendJson(response, 200, { result: { status: "green" } });
      }
      if (request.method === "PUT") {
        collections.add(collection);
        if (!pointsByCollection.has(collection)) pointsByCollection.set(collection, new Map());
        return sendJson(response, 200, { result: true });
      }
    }

    const indexMatch = pathname.match(/^\/collections\/([^/]+)\/index$/);
    if (request.method === "PUT" && indexMatch) {
      const collection = decodeURIComponent(indexMatch[1]);
      indexes.push({ collection, ...body });
      return sendJson(response, 200, { result: true });
    }

    const upsertMatch = pathname.match(/^\/collections\/([^/]+)\/points$/);
    if (request.method === "PUT" && upsertMatch) {
      const collection = decodeURIComponent(upsertMatch[1]);
      const points = pointsByCollection.get(collection) ?? new Map();
      for (const point of body.points ?? []) points.set(point.id, point);
      pointsByCollection.set(collection, points);
      return sendJson(response, 200, { result: { operation_id: 1, status: "completed" } });
    }

    const scrollMatch = pathname.match(/^\/collections\/([^/]+)\/points\/scroll$/);
    if (request.method === "POST" && scrollMatch) {
      const collection = decodeURIComponent(scrollMatch[1]);
      const points = [...(pointsByCollection.get(collection)?.values() ?? [])]
        .filter((point) => matchesQdrantFilter(point.payload, body.filter))
        .slice(0, body.limit ?? 10);
      return sendJson(response, 200, { result: { points, next_page_offset: null } });
    }

    const searchMatch = pathname.match(/^\/collections\/([^/]+)\/points\/search$/);
    if (request.method === "POST" && searchMatch) {
      const collection = decodeURIComponent(searchMatch[1]);
      const points = [...(pointsByCollection.get(collection)?.values() ?? [])]
        .filter((point) => matchesQdrantFilter(point.payload, body.filter))
        .map((point) => ({ ...point, score: cosine(body.vector, point.vector) }))
        .sort((left, right) => right.score - left.score)
        .slice(0, body.limit ?? 10);
      return sendJson(response, 200, { result: points });
    }

    return sendJson(response, 404, { status: { error: "not found" } });
  });

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  return {
    url: `http://127.0.0.1:${port}`,
    state: {
      collections,
      indexes,
      pointsFor: (collection) => pointsByCollection.get(collection) ?? new Map()
    },
    stop: () => new Promise((resolve) => server.close(resolve))
  };
}

async function readJsonBody(request) {
  let raw = "";
  for await (const chunk of request) raw += chunk;
  return raw ? JSON.parse(raw) : {};
}

function sendJson(response, status, body) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" }
  });
}

async function runConnectCallbackSmoke(app, env, expectedAuthUrlPattern, localFetch = fetch) {
  const server = createMcpServer(app, env);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    const connect = await localFetch(`http://127.0.0.1:${port}/connect?format=json`);
    const payload = await connect.json();
    assert.equal(connect.status, 200);
    assert.match(payload.authUrl, expectedAuthUrlPattern);
    const state = new URL(payload.authUrl).searchParams.get("state");
    assert(state);

    const callback = await localFetch(`http://127.0.0.1:${port}/oauth/callback?code=test-code&state=${encodeURIComponent(state)}`);
    const html = await callback.text();
    assert.equal(callback.status, 200);
    assert.match(html, /connected/i);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function restoreEnv(key, value) {
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
}

function matchesQdrantFilter(payload, filter) {
  if (!filter?.must?.length) return true;
  return filter.must.every((condition) => {
    const actual = payload[condition.key];
    if (Object.hasOwn(condition.match ?? {}, "value")) {
      return Array.isArray(actual) ? actual.includes(condition.match.value) : actual === condition.match.value;
    }
    if (Object.hasOwn(condition.match ?? {}, "any")) {
      return Array.isArray(actual) ? condition.match.any.some((value) => actual.includes(value)) : condition.match.any.includes(actual);
    }
    return true;
  });
}

function cosine(left, right) {
  if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length || left.length === 0) return 0;
  let dot = 0;
  let leftMagnitude = 0;
  let rightMagnitude = 0;
  for (let index = 0; index < left.length; index += 1) {
    dot += left[index] * right[index];
    leftMagnitude += left[index] ** 2;
    rightMagnitude += right[index] ** 2;
  }
  return dot / (Math.sqrt(leftMagnitude) * Math.sqrt(rightMagnitude));
}
