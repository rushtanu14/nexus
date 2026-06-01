import crypto from "node:crypto";

const servers = new Map();

export async function registerServer(app, url) {
  if (!app || !url) throw new Error("app and url are required");
  servers.set(app, url);
}

export async function scrapeServer(app) {
  const url = servers.get(app);
  if (!url) throw new Error(`MCP server is not registered: ${app}`);
  const tools = await fetchTools(url);
  return tools.map((tool) => ({
    id: crypto.randomUUID(),
    meta: {
      app,
      category: "mcp",
      action: tool.name,
      label: tool.description || tool.name,
      source: "mcp"
    },
    fields: schemaToFields(tool.inputSchema),
    runner: {
      steps: [{
        primitive: "mcp_call",
        args: {
          server: url,
          tool: tool.name,
          inputs: Object.fromEntries(schemaToFields(tool.inputSchema).map((field) => [field.id, `{{fields.${field.id}}}`]))
        }
      }],
      output_binding: null
    },
    mcp: { server: url, tool: tool.name }
  }));
}

export async function listServers() {
  return Object.fromEntries(servers);
}

export function clearServers() {
  servers.clear();
}

async function fetchTools(url) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: crypto.randomUUID(), method: "tools/list", params: {} })
  });
  if (!response.ok) throw new Error(`MCP tools/list failed with HTTP ${response.status}`);
  const payload = await response.json();
  if (payload.error) throw new Error(payload.error.message ?? "MCP tools/list failed");
  return payload.result?.tools ?? payload.tools ?? [];
}

function schemaToFields(schema = {}) {
  const required = new Set(schema.required ?? []);
  return Object.entries(schema.properties ?? {}).map(([id, property]) => ({
    id,
    type: fieldType(property),
    required: required.has(id),
    label: property.description || property.title || id,
    value: required.has(id) ? `{{context.${id}}}` : ""
  }));
}

function fieldType(property) {
  if (property.enum) return "select";
  if (["string", "number", "boolean"].includes(property.type)) return property.type;
  return "string";
}
