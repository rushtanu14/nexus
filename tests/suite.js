import assert from "node:assert/strict";
import fs from "node:fs/promises";
import http from "node:http";
import test from "node:test";
import { executeNode } from "../src/executor.js";
import { configureGenerator, generateNode, getGenerationCount, resetGenerationCount } from "../src/generator.js";
import { createLifePlan } from "../src/life-assistant.js";
import { clearServers, registerServer, scrapeServer } from "../src/mcp-registry.js";
import { validateNode, validateSchema } from "../src/node-schema.js";
import { clearNodes, findNode, saveNode } from "../src/node-store.js";
import { configureRunners, resetRunners, RUNNERS } from "../src/runners/index.js";
import { createServer } from "../src/server.js";

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
  assert(plan.automations.some((automation) => automation.id === "automation-open-resource"));
  assert(plan.warnings.some((warning) => warning.includes("dry run")));
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
