import crypto from "node:crypto";
import { findNode, saveNode } from "./node-store.js";
import { templateReferences, validateNode } from "./node-schema.js";

const PRIMITIVES = [
  "browser_goto", "browser_extract", "browser_click", "browser_fill",
  "fs_read", "fs_write", "shell_run", "http_request", "mcp_call", "ai_infer"
];

export const OLLAMA_MODEL = process.env.OLLAMA_MODEL ?? "qwen2.5-coder:7b";
export const OLLAMA_BASE_URL = process.env.OLLAMA_BASE_URL ?? "http://127.0.0.1:11434";
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

let planner = ollamaPlanner;
let generationCount = 0;

export function configureGenerator({ generate } = {}) {
  planner = generate ?? ollamaPlanner;
}

export function getGenerationCount() {
  return generationCount;
}

export function resetGenerationCount() {
  generationCount = 0;
}

export async function generateNode(intent, context = {}) {
  if (typeof intent !== "string" || !intent.trim()) throw new Error("intent is required");
  const saved = await findNode(intent);
  if (saved) {
    try {
      validateNode(saved, { context });
      validateRequiredFieldBindings(saved, context);
      return saved;
    } catch {
      // Ignore nodes saved under an older contract and regenerate them.
    }
  }

  generationCount += 1;
  let correction = null;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const generated = await planner(intent.trim(), context, correction);
    if (generated?.error === "cannot_map") return generated;
    try {
      const node = normalizeGeneratedNode(generated);
      validateNode(node, { context });
      validateRequiredFieldBindings(node, context);
      await saveNode(node, intent);
      return node;
    } catch (error) {
      correction = error.message;
    }
  }
  throw new Error(`Local model could not produce an executable node: ${correction}`);
}

export async function ollamaPlanner(intent, context = {}, correction = null) {
  const response = await fetch(`${OLLAMA_BASE_URL}/api/chat`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      model: OLLAMA_MODEL,
      stream: false,
      format: "json",
      options: { temperature: 0, seed: 42 },
      messages: [
        { role: "system", content: systemPrompt() },
        { role: "user", content: JSON.stringify({ intent, context, correction }) }
      ]
    }),
    signal: AbortSignal.timeout(Number(process.env.OLLAMA_TIMEOUT_MS ?? 120000))
  }).catch((error) => {
    throw new Error(`Local model unavailable at ${OLLAMA_BASE_URL}: ${error.message}`);
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`Local model request failed with HTTP ${response.status}: ${detail}`);
  }
  const payload = await response.json();
  const content = payload.message?.content;
  if (typeof content !== "string") throw new Error("Local model returned no JSON content");
  try {
    return JSON.parse(content);
  } catch {
    throw new Error("Local model returned invalid JSON");
  }
}

function validateRequiredFieldBindings(node, context) {
  for (const field of node.fields.filter((candidate) => candidate.required)) {
    for (const reference of templateReferences(field.value)) {
      if (!reference.startsWith("context.")) continue;
      const normalized = reference.startsWith("context.") ? reference.slice("context.".length) : reference;
      const resolved = normalized.split(".").reduce((current, key) => current?.[key], context);
      if (resolved === undefined) throw new Error(`required field ${field.id} has unresolved runtime binding ${reference}; use the literal value from the intent`);
    }
  }
}

function normalizeGeneratedNode(node) {
  if (!node || typeof node !== "object" || Array.isArray(node)) throw new Error("Local model returned an invalid node");
  const fields = Array.isArray(node.fields) ? node.fields : [];
  const fieldIds = new Set(fields.map((field) => field?.id).filter((id) => typeof id === "string"));
  return {
    ...node,
    id: typeof node.id === "string" && UUID_PATTERN.test(node.id) ? node.id : crypto.randomUUID(),
    fields,
    runner: normalizeRunner(node.runner, fieldIds),
    meta: { ...node.meta, source: node.meta?.source ?? "manual" },
    mcp: node.mcp ?? null
  };
}

function normalizeRunner(runner, fieldIds) {
  if (!runner || typeof runner !== "object" || Array.isArray(runner)) return runner;
  return {
    ...runner,
    steps: Array.isArray(runner.steps)
      ? runner.steps.map((step) => ({
          ...step,
          args: normalizeBindingsDeep(step?.args ?? {}, fieldIds)
        }))
      : runner.steps,
    output_binding: normalizeBindings(runner.output_binding, fieldIds)
  };
}

function normalizeBindingsDeep(value, fieldIds) {
  if (typeof value === "string") return normalizeBindings(value, fieldIds);
  if (Array.isArray(value)) return value.map((item) => normalizeBindingsDeep(item, fieldIds));
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, normalizeBindingsDeep(item, fieldIds)]));
}

function normalizeBindings(value, fieldIds) {
  if (typeof value !== "string") return value;
  return value.replace(/\{\{\s*([^{}.]+)\s*\}\}/g, (match, reference) => {
    return fieldIds.has(reference) ? `{{fields.${reference}}}` : match;
  });
}

function systemPrompt() {
  return `You generate one executable workflow node for a local automation engine.

Return only a JSON object. Never use markdown.

Available primitive runners and exact arguments:
browser_goto: { "url": "string" }
browser_extract: { "selector": "string", "attribute": "string" }
browser_click: { "selector": "string" }
browser_fill: { "selector": "string", "value": "string" }
fs_read: { "path": "string" }
fs_write: { "path": "string", "content": "string" }
shell_run: { "command": "string" }
http_request: { "url": "string", "method": "string", "body": "optional object or string" }
mcp_call: { "server": "string", "tool": "string", "inputs": "object" }
ai_infer: { "prompt": "string", "context": "object" }

Required node shape:
{
  "id": "optional UUID; omit if needed",
  "meta": { "app": "string", "category": "string", "action": "string", "label": "string", "source": "manual" },
  "fields": [{ "id": "string", "type": "string|number|boolean|select", "required": true, "label": "string", "value": "string" }],
  "runner": {
    "steps": [{ "primitive": "one available primitive", "args": { "argument": "literal or {{fields.id}}" } }],
    "output_binding": null
  },
  "mcp": null
}

Rules:
- Map the user's exact intent to one or more available runner steps.
- Put every concrete value from the intent directly into fields. Do not replace a value stated in the intent with a context binding.
- Use {{context.key}} only when the value is genuinely absent from the intent and present in the supplied context object.
- Runner args may reference fields as {{fields.id}} and earlier outputs as {{steps.0.output}}.
- Use browser_goto before browser_extract, browser_click, or browser_fill when navigating is required.
- Use shell_run only when a narrower primitive cannot express the operation.
- Do not invent primitives.
- Do not execute anything.
- If the user message includes a correction, repair that validation problem in the new JSON node.
- If the intent cannot be expressed, return { "error": "cannot_map", "reason": "specific reason" }.`;
}
