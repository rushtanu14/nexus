#!/usr/bin/env node
import { Buffer } from "node:buffer";
import http from "node:http";
import { loadMcpSecrets, providerAuthStatus } from "./mcp-secret-store.mjs";
import { handleOAuthRoute } from "./mcp-oauth.mjs";

const HOST = process.env.NEXUS_MCP_HOST ?? "127.0.0.1";
const NOTION_VERSION = "2022-06-28";

export const BRIDGES = {
  gmail: {
    port: Number(process.env.NEXUS_MCP_GMAIL_PORT ?? 9001),
    tools: [{
      name: "draft_email",
      aliases: ["gmail_draft_email"],
      description: "Create a Gmail draft from Nexus Echo context.",
      inputSchema: {
        type: "object",
        properties: {
          to: { type: "string", description: "Recipient email address, or comma-separated recipients." },
          to_hint: { type: "string", description: "Recipient hint from the meeting." },
          subject: { type: "string", description: "Draft subject." },
          body: { type: "string", description: "Draft body." },
          cc: { type: "string", description: "Optional CC recipients." },
          bcc: { type: "string", description: "Optional BCC recipients." }
        },
        required: ["subject", "body"]
      },
      call: draftGmail
    }]
  },
  "google-workspace": {
    port: Number(process.env.NEXUS_MCP_GOOGLE_WORKSPACE_PORT ?? 9002),
    tools: [{
      name: "create_calendar_event",
      aliases: ["calendar_create_event", "gcal_create_event"],
      description: "Create a Google Calendar event.",
      inputSchema: {
        type: "object",
        properties: {
          title: { type: "string", description: "Event title." },
          start: { type: "string", description: "ISO start datetime." },
          end: { type: "string", description: "ISO end datetime." },
          when: { type: "string", description: "Natural-language time hint." },
          when_hint: { type: "string", description: "Natural-language time hint." },
          attendees: { type: "string", description: "Comma-separated attendee emails." },
          attendees_hint: { type: "string", description: "Comma-separated attendee hints." },
          agenda: { type: "string", description: "Event agenda." },
          notes: { type: "string", description: "Event notes." },
          location: { type: "string", description: "Optional event location." },
          timeZone: { type: "string", description: "IANA timezone." }
        },
        required: ["title"]
      },
      call: createCalendarEvent
    }]
  },
  "google-drive": {
    port: Number(process.env.NEXUS_MCP_GOOGLE_DRIVE_PORT ?? 9003),
    tools: [{
      name: "create_doc",
      aliases: ["google_drive_create_doc", "drive_create_doc"],
      description: "Create a Google Docs document from Nexus notes.",
      inputSchema: {
        type: "object",
        properties: {
          name: { type: "string", description: "Document name." },
          title: { type: "string", description: "Document title." },
          body: { type: "string", description: "Document body." },
          content: { type: "string", description: "Document content." }
        },
        required: ["body"]
      },
      call: createGoogleDoc
    }]
  },
  slack: {
    port: Number(process.env.NEXUS_MCP_SLACK_PORT ?? 9004),
    tools: [
      {
        name: "draft_message",
        aliases: ["slack_draft_message"],
        description: "Create a local Slack message preview. This bridge never posts to Slack.",
        inputSchema: {
          type: "object",
          properties: {
            channel: { type: "string", description: "Slack channel ID or #channel name." },
            channel_hint: { type: "string", description: "Slack channel hint." },
            message: { type: "string", description: "Message body." }
          },
          required: ["message"]
        },
        call: previewSlackMessage
      },
      {
        name: "list_channels",
        aliases: ["slack_list_channels"],
        description: "Read Slack channel names and IDs using a read-scoped token.",
        inputSchema: {
          type: "object",
          properties: {
            limit: { type: "number", description: "Maximum channels to return." },
            cursor: { type: "string", description: "Optional Slack pagination cursor." },
            types: { type: "string", description: "Slack channel types, comma-separated." }
          }
        },
        call: listSlackChannels
      },
      {
        name: "search_messages",
        aliases: ["slack_search_messages"],
        description: "Search Slack messages using a read-scoped token.",
        inputSchema: {
          type: "object",
          properties: {
            query: { type: "string", description: "Slack search query." },
            count: { type: "number", description: "Maximum results to return." },
            sort: { type: "string", description: "timestamp or score." }
          },
          required: ["query"]
        },
        call: searchSlackMessages
      }
    ]
  },
  notion: {
    port: Number(process.env.NEXUS_MCP_NOTION_PORT ?? 9005),
    tools: [{
      name: "create_tasks",
      aliases: ["notion_create_page"],
      description: "Create a Notion page with captured tasks or notes.",
      inputSchema: {
        type: "object",
        properties: {
          title: { type: "string", description: "Page title." },
          tasks: { type: "string", description: "Task list, one per line." },
          content: { type: "string", description: "Page content." },
          context: { type: "string", description: "Meeting context." },
          parent_page_id: { type: "string", description: "Notion parent page ID override." }
        },
        required: ["title"]
      },
      call: createNotionPage
    }]
  }
};

export function createMcpServer(app, env = process.env) {
  const bridge = BRIDGES[app];
  if (!bridge) throw new Error(`Unknown MCP bridge app: ${app}`);
  return http.createServer(async (request, response) => {
    try {
      if (request.method === "GET" && request.url === "/health") {
        const auth = await providerAuthStatus(env);
        return sendJson(response, 200, {
          ok: true,
          app,
          tools: bridge.tools.map((tool) => tool.name),
          auth: auth[authProviderForApp(app)]
        });
      }
      if (request.method === "GET" && request.url.startsWith("/connectors")) {
        return sendConnectorPage(response, await providerAuthStatus(env), request);
      }
      if (await handleOAuthRoute(app, request, response, env)) return;
      if (request.method !== "POST") return sendJson(response, 405, { error: "method_not_allowed" });
      const payload = await readJson(request);
      const result = await handleJsonRpc(app, payload, env);
      sendJson(response, 200, result);
    } catch (error) {
      sendJson(response, 200, {
        jsonrpc: "2.0",
        id: null,
        error: { code: -32000, message: error.message }
      });
    }
  });
}

export async function startBridges({ apps = Object.keys(BRIDGES), host = HOST, env = process.env } = {}) {
  const servers = [];
  for (const app of apps) {
    const server = createMcpServer(app, env);
    const port = BRIDGES[app].port;
    await new Promise((resolve) => server.listen(port, host, resolve));
    servers.push({ app, host, port, url: `http://${host}:${port}`, server });
  }
  return servers;
}

export async function handleJsonRpc(app, payload, env = process.env) {
  const bridge = BRIDGES[app];
  if (!bridge) throw new Error(`Unknown MCP bridge app: ${app}`);
  if (payload.method === "tools/list") {
    return {
      jsonrpc: "2.0",
      id: payload.id,
      result: {
        tools: bridge.tools.map(({ name, description, inputSchema }) => ({ name, description, inputSchema }))
      }
    };
  }
  if (payload.method === "tools/call") {
    const name = payload.params?.name;
    const tool = bridge.tools.find((item) => item.name === name || item.aliases?.includes(name));
    if (!tool) throw new Error(`${app} does not expose tool ${name}`);
    const inputs = payload.params?.arguments ?? payload.params?.inputs ?? {};
    return {
      jsonrpc: "2.0",
      id: payload.id,
      result: await tool.call(inputs, env)
    };
  }
  return {
    jsonrpc: "2.0",
    id: payload.id,
    error: { code: -32601, message: `Unknown JSON-RPC method: ${payload.method}` }
  };
}

async function draftGmail(inputs, env) {
  const token = await googleAccessToken(env);
  const to = recipientHeader(inputs.to ?? inputs.to_hint);
  const raw = base64Url([
    to ? `To: ${to}` : "",
    inputs.cc ? `Cc: ${inputs.cc}` : "",
    inputs.bcc ? `Bcc: ${inputs.bcc}` : "",
    `Subject: ${inputs.subject ?? "Nexus follow-up"}`,
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=UTF-8",
    "",
    inputs.body ?? inputs.context ?? ""
  ].filter((line) => line !== "").join("\r\n"));
  const result = await fetchJson("https://gmail.googleapis.com/gmail/v1/users/me/drafts", {
    method: "POST",
    headers: googleHeaders(token),
    body: JSON.stringify({ message: { raw } })
  }, "Gmail draft");
  return { ok: true, provider: "gmail", draftId: result.id, messageId: result.message?.id };
}

async function createCalendarEvent(inputs, env) {
  const token = await googleAccessToken(env);
  const secrets = await loadMcpSecrets(env);
  const timeZone = inputs.timeZone ?? secrets.google.calendarTimeZone ?? "America/Los_Angeles";
  const timing = resolveEventTiming(inputs, timeZone, env);
  const event = {
    summary: inputs.title ?? "Nexus follow-up",
    description: [inputs.agenda, inputs.notes, inputs.context].filter(Boolean).join("\n\n"),
    location: inputs.location,
    attendees: parseEmailList(inputs.attendees ?? inputs.attendees_hint).map((email) => ({ email })),
    start: { dateTime: timing.start, timeZone },
    end: { dateTime: timing.end, timeZone }
  };
  const calendarId = encodeURIComponent(secrets.google.calendarId ?? "primary");
  const result = await fetchJson(`https://www.googleapis.com/calendar/v3/calendars/${calendarId}/events`, {
    method: "POST",
    headers: googleHeaders(token),
    body: JSON.stringify(event)
  }, "Google Calendar event");
  return { ok: true, provider: "google-workspace", eventId: result.id, htmlLink: result.htmlLink, assumedTime: timing.assumed };
}

async function createGoogleDoc(inputs, env) {
  const token = await googleAccessToken(env);
  const title = inputs.name ?? inputs.title ?? "Nexus notes";
  const body = inputs.body ?? inputs.content ?? inputs.context ?? "";
  const created = await fetchJson("https://docs.googleapis.com/v1/documents", {
    method: "POST",
    headers: googleHeaders(token),
    body: JSON.stringify({ title })
  }, "Google Docs create");
  if (body.trim()) {
    await fetchJson(`https://docs.googleapis.com/v1/documents/${created.documentId}:batchUpdate`, {
      method: "POST",
      headers: googleHeaders(token),
      body: JSON.stringify({ requests: [{ insertText: { location: { index: 1 }, text: body } }] })
    }, "Google Docs write");
  }
  return { ok: true, provider: "google-drive", documentId: created.documentId, title };
}

async function previewSlackMessage(inputs) {
  const channel = slackChannel(inputs.channel ?? inputs.channel_hint);
  const message = String(inputs.message ?? inputs.context ?? "").trim();
  if (!message) throw new Error("Slack needs message text.");
  return {
    ok: true,
    provider: "slack",
    readOnly: true,
    preview: true,
    channel: channel || "unselected",
    message,
    note: "Slack bridge is read-only. No Slack message was posted."
  };
}

async function listSlackChannels(inputs, env) {
  const token = await slackReadToken(env);
  const params = new URLSearchParams({
    limit: String(Math.min(Number(inputs.limit ?? 50) || 50, 200)),
    types: inputs.types ?? "public_channel,private_channel"
  });
  if (inputs.cursor) params.set("cursor", inputs.cursor);
  const result = await fetchJson(`https://slack.com/api/conversations.list?${params}`, {
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json; charset=utf-8"
    }
  }, "Slack channel list");
  if (!result.ok) throw new Error(`Slack channel list failed: ${result.error ?? "unknown_error"}`);
  return {
    ok: true,
    provider: "slack",
    readOnly: true,
    channels: (result.channels ?? []).map((channel) => ({
      id: channel.id,
      name: channel.name,
      is_private: Boolean(channel.is_private),
      is_archived: Boolean(channel.is_archived)
    })),
    next_cursor: result.response_metadata?.next_cursor ?? ""
  };
}

async function searchSlackMessages(inputs, env) {
  const token = await slackReadToken(env);
  const query = String(inputs.query ?? "").trim();
  if (!query) throw new Error("Slack search needs query.");
  const params = new URLSearchParams({
    query,
    count: String(Math.min(Number(inputs.count ?? 20) || 20, 100)),
    sort: inputs.sort ?? "timestamp"
  });
  const result = await fetchJson(`https://slack.com/api/search.messages?${params}`, {
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json; charset=utf-8"
    }
  }, "Slack message search");
  if (!result.ok) throw new Error(`Slack message search failed: ${result.error ?? "unknown_error"}`);
  return {
    ok: true,
    provider: "slack",
    readOnly: true,
    total: result.messages?.total ?? 0,
    matches: (result.messages?.matches ?? []).map((match) => ({
      channel_id: match.channel?.id,
      channel_name: match.channel?.name,
      user: match.user,
      text: match.text,
      ts: match.ts,
      permalink: match.permalink
    }))
  };
}

async function createNotionPage(inputs, env) {
  const secrets = await loadMcpSecrets(env);
  const token = secrets.notion.token;
  if (!token) throw new Error("Notion needs NOTION_TOKEN in the shell running the bridge.");
  const parentPageId = inputs.parent_page_id ?? secrets.notion.parentPageId;
  const databaseId = secrets.notion.databaseId;
  if (!parentPageId && !databaseId) throw new Error("Notion needs NOTION_PARENT_PAGE_ID or NOTION_DATABASE_ID.");
  const title = inputs.title ?? "Nexus action items";
  const children = notionBlocks(inputs);
  const parent = databaseId ? { database_id: databaseId } : { page_id: parentPageId };
  const titleProperty = databaseId ? (secrets.notion.titleProperty ?? "Name") : "title";
  const result = await fetchJson("https://api.notion.com/v1/pages", {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
      "notion-version": NOTION_VERSION
    },
    body: JSON.stringify({
      parent,
      properties: {
        [titleProperty]: {
          title: [{ text: { content: title.slice(0, 200) } }]
        }
      },
      children
    })
  }, "Notion page");
  return { ok: true, provider: "notion", pageId: result.id, url: result.url };
}

async function googleAccessToken(env) {
  const secrets = await loadMcpSecrets(env);
  const refreshToken = secrets.google.refreshToken;
  const clientId = secrets.google.clientId;
  const clientSecret = secrets.google.clientSecret;
  if (!refreshToken && secrets.google.accessToken) return secrets.google.accessToken;
  if (!refreshToken || !clientId || !clientSecret) {
    throw new Error("Google needs GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, and GOOGLE_REFRESH_TOKEN, or a temporary GOOGLE_ACCESS_TOKEN.");
  }
  const body = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    refresh_token: refreshToken,
    grant_type: "refresh_token"
  });
  const result = await fetchJson("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body
  }, "Google OAuth refresh");
  return result.access_token;
}

function resolveEventTiming(inputs, timeZone, env) {
  if (inputs.start && inputs.end) return { start: inputs.start, end: inputs.end, assumed: false };
  if (env.NEXUS_MCP_ASSUME_EVENT_TIME !== "1") {
    throw new Error("Calendar needs exact start/end ISO datetimes. Or set NEXUS_MCP_ASSUME_EVENT_TIME=1 to default fuzzy hints to 9:00 AM tomorrow.");
  }
  const start = nextDefaultDate(inputs.when ?? inputs.when_hint);
  const end = new Date(start.getTime() + 30 * 60 * 1000);
  return {
    start: localIso(start, timeZone),
    end: localIso(end, timeZone),
    assumed: true
  };
}

function nextDefaultDate(hint = "") {
  const now = new Date();
  const lower = String(hint).toLowerCase();
  const dayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
  const date = new Date(now);
  date.setHours(9, 0, 0, 0);
  if (lower.includes("today")) return date;
  const weekday = dayNames.findIndex((day) => lower.includes(day));
  if (weekday >= 0) {
    const delta = (weekday - date.getDay() + 7) || 7;
    date.setDate(date.getDate() + delta);
    return date;
  }
  date.setDate(date.getDate() + 1);
  return date;
}

function localIso(date) {
  const pad = (value) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}:00`;
}

function notionBlocks(inputs) {
  const tasks = String(inputs.tasks ?? "")
    .split(/\r?\n/)
    .map((line) => line.replace(/^[-*]\s*/, "").trim())
    .filter(Boolean)
    .slice(0, 50);
  const intro = String(inputs.content ?? inputs.context ?? "").trim();
  const blocks = [];
  if (intro) blocks.push(paragraphBlock(intro.slice(0, 1900)));
  for (const task of tasks) blocks.push(todoBlock(task.slice(0, 1900)));
  if (blocks.length === 0) blocks.push(paragraphBlock("Captured from Nexus."));
  return blocks;
}

function paragraphBlock(content) {
  return {
    object: "block",
    type: "paragraph",
    paragraph: { rich_text: [{ type: "text", text: { content } }] }
  };
}

function todoBlock(content) {
  return {
    object: "block",
    type: "to_do",
    to_do: { rich_text: [{ type: "text", text: { content } }], checked: false }
  };
}

function googleHeaders(token) {
  return {
    authorization: `Bearer ${token}`,
    "content-type": "application/json"
  };
}

function recipientHeader(value) {
  const text = String(value ?? "").trim();
  if (!text || /infer from/i.test(text)) return "";
  return text;
}

function parseEmailList(value) {
  return String(value ?? "")
    .split(/[,\s]+/)
    .map((item) => item.trim())
    .filter((item) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(item));
}

function slackChannel(value) {
  const text = String(value ?? "").trim();
  if (!text || /infer from/i.test(text)) return "";
  return text;
}

async function slackReadToken(env) {
  const secrets = await loadMcpSecrets(env);
  const token = secrets.slack.userToken ?? secrets.slack.botToken;
  if (!token) throw new Error("Slack read access needs SLACK_USER_TOKEN or SLACK_BOT_TOKEN with read-only Slack scopes.");
  return token;
}

function authProviderForApp(app) {
  if (app === "gmail" || app === "google-workspace" || app === "google-drive") return "google";
  return app;
}

function sendConnectorPage(response, status, request) {
  const originHost = request.headers.host?.split(":")[0] ?? HOST;
  const rows = Object.entries(BRIDGES).map(([app, bridge]) => {
    const auth = status[authProviderForApp(app)] ?? {};
    const state = auth.connected ? "Connected" : auth.connectReady ? "Ready to approve" : "Server setup needed";
    const detail = auth.connected
      ? "A provider test call passed and credentials are stored server-side."
      : auth.connectReady
        ? "Click Connect to approve access."
        : "This connector is not configured on the Nexus server yet.";
    return `
      <section>
        <div>
          <h2>${escapeHtml(labelForApp(app))}</h2>
          <p><strong>${escapeHtml(state)}</strong> - ${escapeHtml(detail)}</p>
        </div>
        <a class="button" href="http://${escapeHtml(originHost)}:${bridge.port}/connect">Connect ${escapeHtml(labelForApp(app))}</a>
      </section>
    `;
  }).join("\n");
  sendHtml(response, 200, `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Connect MCP</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 40px auto; max-width: 840px; padding: 0 20px; color: #171717; }
    h1 { margin-bottom: 8px; }
    section { display: flex; align-items: center; justify-content: space-between; gap: 20px; border: 1px solid #dedede; border-radius: 8px; padding: 16px; margin: 12px 0; }
    h2 { margin: 0 0 4px; font-size: 18px; }
    p { margin: 0; color: #525252; }
    .button { display: inline-block; white-space: nowrap; background: #111; color: white; text-decoration: none; border-radius: 8px; padding: 10px 14px; }
    @media (max-width: 640px) { section { align-items: stretch; flex-direction: column; } .button { text-align: center; } }
  </style>
</head>
<body>
  <h1>Connect MCP</h1>
  <p>Choose a connector, approve access, then return here. Credentials are stored server-side.</p>
  ${rows}
</body>
</html>`);
}

function labelForApp(app) {
  return {
    gmail: "Gmail",
    "google-workspace": "Google Calendar",
    "google-drive": "Google Drive",
    slack: "Slack",
    notion: "Notion"
  }[app] ?? app;
}

function sendHtml(response, status, body) {
  response.writeHead(status, { "content-type": "text/html; charset=utf-8" });
  response.end(body);
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function base64Url(value) {
  return Buffer.from(value, "utf8").toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function fetchJson(url, options, label) {
  const response = await fetch(url, options);
  const text = await response.text();
  let payload = {};
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch {
      payload = { raw: text };
    }
  }
  if (!response.ok) throw new Error(`${label} failed with HTTP ${response.status}: ${text.slice(0, 400)}`);
  return payload;
}

function sendJson(response, status, payload) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(payload));
}

async function readJson(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  if (chunks.length === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function selectedApps(argv) {
  const onlyIndex = argv.findIndex((arg) => arg === "--only" || arg === "--apps");
  const selected = onlyIndex >= 0 ? argv[onlyIndex + 1] : process.env.NEXUS_MCP_APPS;
  if (!selected) return Object.keys(BRIDGES);
  return selected.split(",").map((item) => item.trim()).filter(Boolean);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const apps = selectedApps(process.argv.slice(2));
  const servers = await startBridges({ apps });
  for (const { app, url } of servers) {
    console.log(`${app} MCP bridge listening at ${url}`);
  }
}
