import crypto from "node:crypto";
import { actionStore, normalizeAction } from "../store/ActionStore.js";
import { InferenceBuffer } from "./InferenceBuffer.js";

const DEFAULT_THRESHOLD = Number(process.env.NEX_ECHO_CONFIDENCE_THRESHOLD ?? 0.7);
const DEFAULT_INTERVAL_WORDS = Number(process.env.NEX_ECHO_INFERENCE_INTERVAL_WORDS ?? 15);

export class ActionInferrer {
  constructor({
    store = actionStore,
    complete,
    confidenceThreshold = DEFAULT_THRESHOLD,
    intervalWords = DEFAULT_INTERVAL_WORDS,
    windowMs = 60_000
  } = {}) {
    this.store = store;
    this.complete = complete;
    this.confidenceThreshold = confidenceThreshold;
    this.intervalWords = intervalWords;
    this.buffers = new Map();
    this.lastInferenceWordCount = new Map();
    this.seen = new Set();
    this.windowMs = windowMs;
  }

  async handleChunk({ sessionId = "default", text, title = "Echo meeting", notes = "", brain = {} } = {}) {
    const buffer = this.bufferFor(sessionId);
    buffer.add(text);
    const wordCount = buffer.wordCount();
    const previous = this.lastInferenceWordCount.get(sessionId) ?? 0;
    if (wordCount - previous < this.intervalWords) return [];
    this.lastInferenceWordCount.set(sessionId, wordCount);
    return this.infer({ sessionId, title, notes, brain });
  }

  async infer({ sessionId = "default", title = "Echo meeting", notes = "", brain = {} } = {}) {
    const bufferText = this.bufferFor(sessionId).text();
    if (!bufferText) return [];
    const rawActions = await this.modelActions({ bufferText, title, notes, brain });
    const accepted = rawActions
      .map((action) => normalizeAction({ ...action, sessionId }))
      .filter((action) => action.confidence >= this.confidenceThreshold)
      .filter((action) => this.markIfNew(action));
    for (const action of accepted) this.store.upsertAction(action, { sessionId });
    return accepted;
  }

  bufferFor(sessionId) {
    const id = sessionId || "default";
    if (!this.buffers.has(id)) this.buffers.set(id, new InferenceBuffer({ windowMs: this.windowMs }));
    return this.buffers.get(id);
  }

  markIfNew(action) {
    const quote = action.source_quote.toLowerCase().replace(/\s+/g, " ").trim();
    const prefix = `${action.sessionId}:${action.tool}:`;
    for (const existing of this.seen) {
      if (!existing.startsWith(prefix)) continue;
      const existingQuote = existing.slice(prefix.length);
      if (existingQuote.includes(quote) || quote.includes(existingQuote)) return false;
    }
    const key = `${prefix}${quote}`;
    if (this.seen.has(key)) return false;
    this.seen.add(key);
    return true;
  }

  async modelActions({ bufferText, title, notes, brain }) {
    const fallback = inferHeuristicActions({ bufferText, title, notes });
    if (!this.complete) return fallback;

    const prompt = buildInferencePrompt({ bufferText, title, notes });
    try {
      const completion = await this.complete(prompt, brain);
      const parsed = parseActionArray(completion);
      return parsed.length ? parsed : fallback;
    } catch {
      return fallback;
    }
  }
}

export function buildInferencePrompt({ bufferText, title, notes }) {
  return [
    "You are Nex Echo ActionInferrer. Return only a JSON array.",
    "Find MCP actions implied by an in-progress meeting transcript. Do not wait for sentence completion.",
    "Schema: [{\"type\":\"mcp_action\",\"tool\":\"calendar_create_event|notion_create_page|notion_update_page|gmail_draft_email\",\"params\":{},\"confidence\":0.0,\"source_quote\":\"exact phrase\"}]",
    "Return [] when there is no useful action. Use confidence above 0.7 only for actionable intent.",
    "",
    `Meeting title: ${title}`,
    notes ? `Current notes:\n${notes}` : "Current notes: none",
    `Rolling transcript:\n${bufferText}`
  ].join("\n");
}

export function parseActionArray(text) {
  const source = String(text ?? "").trim();
  if (!source) return [];
  const fenced = source.match(/```(?:json)?\s*([\s\S]*?)```/i)?.[1];
  const candidate = fenced ?? source.match(/\[[\s\S]*\]/)?.[0] ?? source;
  try {
    const parsed = JSON.parse(candidate);
    return Array.isArray(parsed) ? parsed.filter((item) => item?.type === "mcp_action" || item?.tool) : [];
  } catch {
    return [];
  }
}

export function inferHeuristicActions({ bufferText, title = "Echo meeting", notes = "" } = {}) {
  const context = [notes, bufferText].filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
  const lower = context.toLowerCase();
  const actions = [];

  const calendarQuote = quoteAround(context, /\b(book|schedule|calendar|meet|meeting|call)\b/i);
  if (calendarQuote && /\b(tomorrow|today|monday|tuesday|wednesday|thursday|friday|saturday|sunday|\d{1,2}(?::\d{2})?\s*(am|pm))\b/i.test(context)) {
    actions.push({
      type: "mcp_action",
      tool: "calendar_create_event",
      params: {
        title: calendarTitle(context, title),
        when: inferWhen(context),
        attendees: inferPeople(context).join(", "),
        notes: context
      },
      confidence: lower.includes("book") || lower.includes("schedule") ? 0.88 : 0.76,
      source_quote: calendarQuote
    });
  }

  const emailQuote = quoteAround(context, /\b(send|draft|email|follow up|follow-up)\b/i);
  if (emailQuote && /\b(email|follow up|follow-up|send|draft)\b/i.test(context)) {
    actions.push({
      type: "mcp_action",
      tool: "gmail_draft_email",
      params: {
        subject: calendarTitle(context, title),
        to: inferPeople(context).join(", "),
        body: notes || context
      },
      confidence: 0.79,
      source_quote: emailQuote
    });
  }

  const notionQuote = quoteAround(context, /\b(notion|notes|action items|tasks|recap|design|engineering|eng)\b/i);
  if (notionQuote && /\b(notion|notes|action items|tasks|recap|meeting notes|design|engineering|eng)\b/i.test(context)) {
    actions.push({
      type: "mcp_action",
      tool: "notion_create_page",
      params: {
        title: notionTitle(context, title),
        content: notes || context
      },
      confidence: /\b(action items|tasks|notion)\b/i.test(context) ? 0.84 : 0.72,
      source_quote: notionQuote
    });
  }

  return actions.map((action) => ({ id: crypto.randomUUID(), ...action }));
}

function quoteAround(text, pattern) {
  const match = text.match(pattern);
  if (!match || match.index == null) return "";
  const start = Math.max(0, match.index - 70);
  const end = Math.min(text.length, match.index + 130);
  return text.slice(start, end).trim();
}

function inferWhen(text) {
  const time = text.match(/\b\d{1,2}(?::\d{2})?\s*(am|pm)\b/i)?.[0] ?? "";
  const day = text.match(/\b(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/i)?.[0] ?? "";
  return [day, time].filter(Boolean).join(" ") || "Infer from transcript";
}

function inferPeople(text) {
  const stop = new Set(["Nex", "Echo", "Meeting", "Calendar", "Notion", "Gmail", "Design", "Engineering"]);
  return [...new Set([...text.matchAll(/\b[A-Z][a-z]{2,}\b/g)].map((match) => match[0]).filter((name) => !stop.has(name)))].slice(0, 6);
}

function calendarTitle(text, fallback) {
  const project = text.match(/\b(?:about|for|on)\s+([A-Za-z][A-Za-z0-9 -]{3,40})/i)?.[1];
  return project ? `${project.trim()} sync` : fallback;
}

function notionTitle(text, fallback) {
  if (/\bdesign\b/i.test(text)) return `${fallback} design notes`;
  if (/\beng|engineering\b/i.test(text)) return `${fallback} engineering notes`;
  if (/\baction items|tasks\b/i.test(text)) return `${fallback} action items`;
  return `${fallback} notes`;
}
