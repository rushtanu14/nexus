import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";

const servers = new Map();
const connectors = new Map();
const STORE_PATH = process.env.NEXUS_MCP_STORE ?? path.join(process.cwd(), ".nexus-data", "mcp-connectors.sqlite");
fs.mkdirSync(path.dirname(STORE_PATH), { recursive: true });
const database = new Database(STORE_PATH);
database.pragma("journal_mode = WAL");
database.exec(`
  CREATE TABLE IF NOT EXISTS connectors (
    app TEXT PRIMARY KEY,
    id TEXT NOT NULL,
    url TEXT NOT NULL,
    headers_json TEXT NOT NULL,
    status TEXT NOT NULL,
    auth_type TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
`);
const upsertConnector = database.prepare(`
  INSERT INTO connectors (app, id, url, headers_json, status, auth_type, updated_at)
  VALUES (@app, @id, @url, @headersJson, @status, @authType, @updatedAt)
  ON CONFLICT(app) DO UPDATE SET
    id = excluded.id,
    url = excluded.url,
    headers_json = excluded.headers_json,
    status = excluded.status,
    auth_type = excluded.auth_type,
    updated_at = excluded.updated_at
`);
const selectConnectors = database.prepare("SELECT * FROM connectors");
const deleteConnectors = database.prepare("DELETE FROM connectors");

const REGISTRY = [
  {
    id: "google-workspace",
    name: "Google Workspace",
    servers: ["google-workspace", "gcal", "google-calendar"],
    auth: "oauth_bearer",
    tools: ["create_calendar_event", "list_calendar_events"],
    description: "Calendar event creation and schedule sync for inferred meetings."
  },
  {
    id: "gmail",
    name: "Gmail",
    servers: ["gmail"],
    auth: "oauth_bearer",
    tools: ["draft_email", "send_email"],
    description: "Email drafts and follow-up handoffs from Echo or calendar context."
  },
  {
    id: "notion",
    name: "Notion",
    servers: ["notion"],
    auth: "bearer",
    tools: ["create_page", "create_tasks", "update_page"],
    description: "Pages, tasks, and project schedules for meeting action items."
  },
  {
    id: "slack",
    name: "Slack",
    servers: ["slack"],
    auth: "oauth_bearer",
    tools: ["draft_message", "post_message"],
    description: "Team updates and sync-up reminders."
  },
  {
    id: "google-drive",
    name: "Google Drive",
    servers: ["google-drive"],
    auth: "oauth_bearer",
    tools: ["create_doc", "update_doc"],
    description: "Meeting recap docs and context documents."
  }
];

export async function registerServer(app, url) {
  if (!app || !url) throw new Error("app and url are required");
  saveConnector({ app, id: app, url, headers: {}, status: "registered", authType: "none", updatedAt: new Date().toISOString() });
}

export async function scrapeServer(app) {
  const server = resolveServer(app);
  if (!server) throw new Error(`MCP server is not registered: ${app}`);
  const tools = await fetchTools(server.url, server.headers);
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
          server: app,
          tool: tool.name,
          inputs: Object.fromEntries(schemaToFields(tool.inputSchema).map((field) => [field.id, `{{fields.${field.id}}}`]))
        }
      }],
      output_binding: null
    },
    mcp: { server: app, tool: tool.name }
  }));
}

export async function listServers() {
  return Object.fromEntries([...servers].map(([name, server]) => [name, server.url]));
}

export async function listConnectors() {
  const connected = new Map([...servers, ...connectors]);
  return REGISTRY.map((entry) => {
    const serverName = entry.servers.find((name) => connected.has(name)) ?? entry.id;
    const state = connected.get(serverName);
    return {
      ...entry,
      server: serverName,
      url: state?.url ?? "",
      status: state?.status ?? "available",
      authenticated: Boolean(state?.headers?.authorization || state?.headers?.["x-api-key"]),
      updatedAt: state?.updatedAt ?? null
    };
  });
}

export async function configureConnector({ id, app, url, auth = {}, toolProbe = true } = {}) {
  const registryEntry = REGISTRY.find((entry) => entry.id === id || entry.servers.includes(id) || entry.id === app || entry.servers.includes(app));
  const serverName = app || registryEntry?.servers?.[0] || id;
  if (!serverName || !url) throw new Error("connector id/app and url are required");
  const headers = authHeaders(auth);
  const record = {
    app: serverName,
    id: id ?? serverName,
    url,
    headers,
    status: headers.authorization || headers["x-api-key"] ? "authenticated" : "registered",
    authType: auth.type ?? registryEntry?.auth ?? "none",
    updatedAt: new Date().toISOString()
  };
  if (toolProbe) await fetchTools(url, headers);
  saveConnector(record);
  return sanitizeConnector(record);
}

export async function authenticateConnector({ id, app, url, auth = {} } = {}) {
  return configureConnector({ id, app, url, auth, toolProbe: true });
}

export function resolveServer(nameOrUrl) {
  if (!nameOrUrl) return null;
  if (/^https?:\/\//i.test(nameOrUrl)) return { app: nameOrUrl, url: nameOrUrl, headers: {} };
  return servers.get(nameOrUrl) ?? connectors.get(nameOrUrl) ?? null;
}

export async function callRegisteredTool(serverName, tool, inputs, signal) {
  const server = resolveServer(serverName);
  if (!server) throw new Error(`MCP server is not registered: ${serverName}`);
  const response = await fetch(server.url, {
    method: "POST",
    headers: { "content-type": "application/json", ...server.headers },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: crypto.randomUUID(),
      method: "tools/call",
      params: { name: tool, arguments: inputs }
    }),
    signal
  });
  if (!response.ok) throw new Error(`MCP tools/call failed with HTTP ${response.status}: ${await response.text()}`);
  const payload = await response.json();
  if (payload.error) throw new Error(payload.error.message ?? "MCP tools/call failed");
  return payload.result ?? payload;
}

export function clearServers() {
  servers.clear();
  connectors.clear();
  deleteConnectors.run();
}

loadPersistedConnectors();

function authHeaders(auth) {
  const headers = {};
  if (auth?.accessToken) headers.authorization = `Bearer ${auth.accessToken}`;
  if (auth?.bearerToken) headers.authorization = `Bearer ${auth.bearerToken}`;
  if (auth?.apiKey) headers["x-api-key"] = auth.apiKey;
  return headers;
}

function sanitizeConnector(record) {
  return {
    id: record.id,
    app: record.app,
    url: record.url,
    status: record.status,
    authType: record.authType,
    authenticated: Boolean(record.headers.authorization || record.headers["x-api-key"]),
    updatedAt: record.updatedAt
  };
}

function saveConnector(record) {
  servers.set(record.app, record);
  connectors.set(record.app, record);
  upsertConnector.run({
    app: record.app,
    id: record.id,
    url: record.url,
    headersJson: JSON.stringify(record.headers ?? {}),
    status: record.status,
    authType: record.authType,
    updatedAt: record.updatedAt
  });
}

function loadPersistedConnectors() {
  for (const record of selectConnectors.all()) {
    const connector = {
      app: record.app,
      id: record.id,
      url: record.url,
      headers: JSON.parse(record.headers_json || "{}"),
      status: record.status,
      authType: record.auth_type,
      updatedAt: record.updated_at
    };
    servers.set(connector.app, connector);
    connectors.set(connector.app, connector);
  }
}

async function fetchTools(url, headers = {}) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
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
