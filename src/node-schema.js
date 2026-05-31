import { RUNNERS } from "./runners/index.js";

export const NODE_SCHEMA = {
  type: "object",
  required: ["id", "meta", "fields", "runner", "mcp"],
  properties: {
    id: { type: "string", format: "uuid" },
    meta: {
      type: "object",
      required: ["app", "category", "action", "label", "source"],
      properties: {
        app: { type: "string" },
        category: { type: "string" },
        action: { type: "string" },
        label: { type: "string" },
        source: { enum: ["mcp", "manual", "saved"] }
      }
    },
    fields: {
      type: "array",
      items: {
        type: "object",
        required: ["id", "type", "required", "label", "value"],
        properties: {
          id: { type: "string" },
          type: { enum: ["string", "number", "boolean", "select"] },
          required: { type: "boolean" },
          label: { type: "string" },
          value: { type: "string" }
        }
      }
    },
    runner: {
      type: "object",
      required: ["steps", "output_binding"],
      properties: {
        steps: {
          type: "array",
          minItems: 1,
          items: {
            type: "object",
            required: ["primitive", "args"],
            properties: {
              primitive: { enum: Object.keys(RUNNERS) },
              args: { type: "object" }
            }
          }
        },
        output_binding: { type: ["string", "null"] }
      }
    },
    mcp: {
      anyOf: [
        { type: "null" },
        {
          type: "object",
          required: ["server", "tool"],
          properties: {
            server: { type: "string" },
            tool: { type: "string" }
          }
        }
      ]
    }
  }
};

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const FIELD_TYPES = new Set(["string", "number", "boolean", "select"]);
const SOURCES = new Set(["mcp", "manual", "saved"]);
const TEMPLATE_PATTERN = /\{\{\s*([^{}]+?)\s*\}\}/g;
const RUNNER_ARGUMENTS = {
  browser_goto: { required: ["url"] },
  browser_extract: { required: ["selector", "attribute"] },
  browser_click: { required: ["selector"] },
  browser_fill: { required: ["selector", "value"] },
  fs_read: { required: ["path"] },
  fs_write: { required: ["path", "content"] },
  shell_run: { required: ["command"] },
  http_request: { required: ["url", "method"], optional: ["body"] },
  mcp_call: { required: ["server", "tool", "inputs"] },
  ai_infer: { required: ["prompt", "context"] }
};

function assertObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }
}

function assertString(value, label) {
  if (typeof value !== "string") throw new Error(`${label} must be a string`);
}

export function templateReferences(value) {
  if (typeof value !== "string") return [];
  return [...value.matchAll(TEMPLATE_PATTERN)].map((match) => match[1]);
}

export function validateNode(node, { context = {}, allowUnresolvedContext = true } = {}) {
  assertObject(node, "node");
  assertString(node.id, "node.id");
  if (!UUID_PATTERN.test(node.id)) throw new Error("node.id must be a UUID");

  assertObject(node.meta, "node.meta");
  for (const key of ["app", "category", "action", "label"]) assertString(node.meta[key], `node.meta.${key}`);
  if (!SOURCES.has(node.meta.source)) throw new Error("node.meta.source is invalid");

  if (!Array.isArray(node.fields)) throw new Error("node.fields must be an array");
  const fieldIds = new Set();
  for (const field of node.fields) {
    assertObject(field, "field");
    assertString(field.id, "field.id");
    assertString(field.label, `field.${field.id}.label`);
    assertString(field.value, `field.${field.id}.value`);
    if (fieldIds.has(field.id)) throw new Error(`duplicate field id: ${field.id}`);
    fieldIds.add(field.id);
    if (!FIELD_TYPES.has(field.type)) throw new Error(`invalid field type: ${field.type}`);
    if (typeof field.required !== "boolean") throw new Error(`field.${field.id}.required must be a boolean`);
    if (field.required && !field.value.trim()) throw new Error(`required field has no value: ${field.id}`);
  }

  assertObject(node.runner, "node.runner");
  if (!Array.isArray(node.runner.steps) || node.runner.steps.length === 0) {
    throw new Error("node.runner.steps must contain at least one step");
  }
  if (node.runner.output_binding !== null) assertString(node.runner.output_binding, "node.runner.output_binding");

  node.runner.steps.forEach((step, index) => {
    assertObject(step, `step ${index}`);
    if (!Object.hasOwn(RUNNERS, step.primitive)) throw new Error(`unknown primitive: ${step.primitive}`);
    assertObject(step.args, `step ${index}.args`);
    validateRunnerArguments(step, index);
    for (const value of Object.values(step.args)) {
      if (typeof value !== "string" && (typeof value !== "object" || value === null)) {
        throw new Error(`step ${index} args must contain strings or objects`);
      }
      for (const reference of templateReferencesDeep(value)) {
        validateReference(reference, { fieldIds, context, allowUnresolvedContext, stepIndex: index });
      }
    }
  });

  if (node.runner.output_binding !== null) {
    for (const reference of templateReferences(node.runner.output_binding)) {
      if (reference !== "steps.last.output" && !reference.startsWith("fields.")) {
        throw new Error(`invalid output binding: ${reference}`);
      }
    }
  }

  if (node.mcp !== null) {
    assertObject(node.mcp, "node.mcp");
    assertString(node.mcp.server, "node.mcp.server");
    assertString(node.mcp.tool, "node.mcp.tool");
  }
  return true;
}

function validateRunnerArguments(step, index) {
  const contract = RUNNER_ARGUMENTS[step.primitive];
  for (const argument of contract.required) {
    if (!Object.hasOwn(step.args, argument)) throw new Error(`${step.primitive} step ${index} is missing required argument: ${argument}`);
  }
  const allowed = new Set([...contract.required, ...(contract.optional ?? [])]);
  for (const argument of Object.keys(step.args)) {
    if (!allowed.has(argument)) throw new Error(`${step.primitive} step ${index} has unknown argument: ${argument}`);
  }
}

function templateReferencesDeep(value) {
  if (typeof value === "string") return templateReferences(value);
  if (Array.isArray(value)) return value.flatMap(templateReferencesDeep);
  return Object.values(value).flatMap(templateReferencesDeep);
}

function validateReference(reference, { fieldIds, context, allowUnresolvedContext, stepIndex }) {
  if (reference.startsWith("fields.")) {
    const fieldId = reference.slice("fields.".length);
    if (!fieldIds.has(fieldId)) throw new Error(`unknown field binding: ${reference}`);
    return;
  }
  if (reference.startsWith("steps.")) {
    const [, rawIndex, output] = reference.split(".");
    if (output !== "output" || !/^\d+$/.test(rawIndex) || Number(rawIndex) >= stepIndex) {
      throw new Error(`invalid step binding: ${reference}`);
    }
    return;
  }
  if (reference.startsWith("context.")) {
    if (!allowUnresolvedContext && getPath(context, reference.slice("context.".length)) === undefined) {
      throw new Error(`unknown context binding: ${reference}`);
    }
    return;
  }
  throw new Error(`invalid binding namespace: ${reference}`);
}

function getPath(value, path) {
  return path.split(".").reduce((current, key) => current?.[key], value);
}

export function validateSchema(node) {
  try {
    return validateNode(node);
  } catch {
    return false;
  }
}
