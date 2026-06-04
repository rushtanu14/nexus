import { EventEmitter } from "node:events";
import crypto from "node:crypto";

const DEFAULT_SESSION = "default";

export class ActionStore extends EventEmitter {
  constructor() {
    super();
    this.sessions = new Map();
  }

  getSession(sessionId = DEFAULT_SESSION) {
    const id = sessionId || DEFAULT_SESSION;
    if (!this.sessions.has(id)) {
      this.sessions.set(id, {
        sessionId: id,
        transcript: "",
        chunks: [],
        actions: [],
        updatedAt: new Date().toISOString()
      });
    }
    return this.sessions.get(id);
  }

  appendTranscriptChunk({ sessionId, text, at = new Date() }) {
    const chunkText = String(text ?? "").trim();
    if (!chunkText) return this.getSession(sessionId);
    const session = this.getSession(sessionId);
    const chunk = { id: crypto.randomUUID(), text: chunkText, at: at.toISOString() };
    session.chunks.push(chunk);
    session.transcript = [session.transcript, chunkText].filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
    session.updatedAt = new Date().toISOString();
    this.emit("transcript:chunk", { sessionId: session.sessionId, chunk, session });
    this.emit("change", session);
    return session;
  }

  upsertAction(action, { sessionId } = {}) {
    const session = this.getSession(sessionId ?? action.sessionId);
    const normalized = normalizeAction({ ...action, sessionId: session.sessionId });
    const existingIndex = session.actions.findIndex((item) => item.id === normalized.id);
    if (existingIndex >= 0) {
      session.actions[existingIndex] = { ...session.actions[existingIndex], ...normalized, updatedAt: new Date().toISOString() };
    } else {
      const duplicate = session.actions.find((item) => isDuplicateAction(item, normalized));
      if (duplicate) return duplicate;
      session.actions.unshift(normalized);
      this.emit("action:inferred", normalized);
    }
    session.updatedAt = new Date().toISOString();
    this.emit("change", session);
    return existingIndex >= 0 ? session.actions[existingIndex] : normalized;
  }

  replaceAction(actionId, replacements, { sessionId } = {}) {
    const session = this.getSession(sessionId);
    const index = session.actions.findIndex((item) => item.id === actionId);
    if (index < 0) return null;
    session.actions.splice(index, 1, ...replacements.map((item) => normalizeAction({ ...item, sessionId: session.sessionId })));
    session.updatedAt = new Date().toISOString();
    this.emit("change", session);
    return session.actions;
  }

  updateAction(actionId, patch, { sessionId } = {}) {
    const session = this.getSession(sessionId);
    const action = session.actions.find((item) => item.id === actionId);
    if (!action) return null;
    Object.assign(action, patch, { updatedAt: new Date().toISOString() });
    session.updatedAt = new Date().toISOString();
    this.emit("action:updated", action);
    this.emit("change", session);
    return action;
  }

  cancelAction(actionId, { sessionId, reason = "Canceled by user" } = {}) {
    return this.updateAction(actionId, { status: "canceled", error: reason }, { sessionId });
  }

  pendingActions(sessionId = DEFAULT_SESSION) {
    return this.getSession(sessionId).actions.filter((action) => ["pending", "suggested"].includes(action.status));
  }

  snapshot(sessionId = DEFAULT_SESSION) {
    const session = this.getSession(sessionId);
    return {
      sessionId: session.sessionId,
      transcript: session.transcript,
      chunks: [...session.chunks],
      actions: session.actions.map((action) => ({ ...action })),
      updatedAt: session.updatedAt
    };
  }

  clear(sessionId = DEFAULT_SESSION) {
    this.sessions.delete(sessionId || DEFAULT_SESSION);
    const session = this.getSession(sessionId);
    this.emit("change", session);
    return session;
  }
}

export const actionStore = new ActionStore();

export function normalizeAction(action) {
  const tool = normalizeTool(action.tool ?? action.mcp?.tool ?? "unknown_tool");
  const provider = providerForTool(tool);
  const params = action.params ?? action.mcp?.inputs ?? {};
  const sourceQuote = String(action.source_quote ?? action.sourceQuote ?? action.summary ?? "").trim();
  return {
    id: action.id ?? crypto.randomUUID(),
    kind: action.kind,
    type: action.type ?? "mcp_action",
    sessionId: action.sessionId ?? DEFAULT_SESSION,
    tool,
    pet: action.pet ?? petForTool(tool),
    provider: action.provider ?? provider.name,
    title: action.title ?? titleForTool(tool, params),
    summary: action.summary ?? descriptionForTool(tool, params),
    params,
    confidence: Number(action.confidence ?? 0.75),
    source_quote: sourceQuote,
    status: action.status ?? "pending",
    createdAt: action.createdAt ?? new Date().toISOString(),
    updatedAt: action.updatedAt ?? new Date().toISOString(),
    result: action.result,
    error: action.error,
    mcp: action.mcp ?? {
      server: provider.server,
      tool,
      inputs: stringifyParams(params)
    }
  };
}

function providerForTool(tool) {
  if (tool.startsWith("calendar_") || tool.startsWith("gcal_") || tool === "create_calendar_event") return { name: "Google Calendar", server: "google-workspace" };
  if (tool.startsWith("gmail_") || tool === "draft_email") return { name: "Gmail", server: "gmail" };
  if (tool.startsWith("notion_") || tool === "create_tasks") return { name: "Notion", server: "notion" };
  return { name: "MCP", server: "mcp" };
}

function petForTool(tool) {
  if (tool.startsWith("calendar_") || tool.startsWith("gcal_") || tool === "create_calendar_event") return "Agumon";
  if (tool.startsWith("gmail_") || tool === "draft_email") return "77";
  if (tool.startsWith("notion_") || tool === "create_tasks") return "aqua-wisp";
  return "mcp";
}

function titleForTool(tool, params) {
  if (tool === "calendar_create_event") return `Create calendar event${params.title ? `: ${params.title}` : ""}`;
  if (tool === "gmail_draft_email") return `Draft email${params.subject ? `: ${params.subject}` : ""}`;
  if (tool === "notion_create_page") return `Create Notion page${params.title ? `: ${params.title}` : ""}`;
  if (tool === "notion_update_page") return "Update Notion page";
  return tool.replaceAll("_", " ");
}

function descriptionForTool(tool, params) {
  if (tool === "calendar_create_event") return `Schedule ${params.title ?? "a meeting"} ${params.when ? `for ${params.when}` : "from the conversation"}.`;
  if (tool === "gmail_draft_email") return `Prepare a Gmail draft${params.to ? ` to ${params.to}` : ""}.`;
  if (tool === "notion_create_page") return `Create a Notion page for ${params.title ?? "captured notes"}.`;
  return `Run ${tool} with inferred MCP parameters.`;
}

function stringifyParams(params) {
  return Object.fromEntries(Object.entries(params ?? {}).map(([key, value]) => [key, typeof value === "string" ? value : JSON.stringify(value)]));
}

function normalizeTool(tool) {
  const raw = String(tool ?? "unknown_tool").toLowerCase().trim();
  if (raw.includes("|")) return normalizeTool(raw.split("|")[0]);
  if (raw.includes("gmail") || raw === "draft_email") return "gmail_draft_email";
  if (raw.includes("calendar") || raw.includes("gcal") || raw === "create_calendar_event") return "calendar_create_event";
  if (raw.includes("notion") && raw.includes("update")) return "notion_update_page";
  if (raw.includes("notion") || raw === "create_tasks") return "notion_create_page";
  return raw.replaceAll(/\s+/g, "_");
}

function isDuplicateAction(left, right) {
  if (`${left.sessionId}:${left.id}` === `${right.sessionId}:${right.id}`) return true;
  if (semanticActionKey(left) === semanticActionKey(right)) return true;
  const leftQuote = normalizedQuote(left);
  const rightQuote = normalizedQuote(right);
  return left.sessionId === right.sessionId &&
    left.tool === right.tool &&
    leftQuote &&
    rightQuote &&
    (leftQuote.includes(rightQuote) || rightQuote.includes(leftQuote));
}

function semanticActionKey(action) {
  const params = action.params ?? {};
  const title = stableText(params.title ?? params.subject ?? action.title ?? "");
  const recipient = stableText(params.to ?? params.attendees ?? params.attendees_hint ?? "");
  const when = stableText(params.when ?? params.date ?? params.time ?? params.when_hint ?? "");
  const content = stableText(params.content ?? params.body ?? params.tasks ?? "").slice(0, 80);
  return [action.sessionId, action.tool, title, recipient, when, content].join(":");
}

function normalizedQuote(action) {
  return stableText(action.source_quote ?? "");
}

function stableText(value) {
  return String(value ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9:@.\s-]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
