import crypto from "node:crypto";
import { actionStore, normalizeAction } from "../store/ActionStore.js";

export class NexAssistant {
  constructor({ store = actionStore, complete, spawner } = {}) {
    this.store = store;
    this.complete = complete;
    this.spawner = spawner;
  }

  async handleMessage({ sessionId = "default", message, brain = {} } = {}) {
    const text = String(message ?? "").trim();
    if (!text) return { mutations: [], snapshot: this.store.snapshot(sessionId) };
    const modelMutations = await this.modelMutations({ sessionId, message: text, brain });
    const mutations = modelMutations.length ? modelMutations : inferQueueMutations(this.store.snapshot(sessionId), text);
    const applied = this.applyMutations(sessionId, mutations);
    return { mutations: applied, snapshot: this.store.snapshot(sessionId) };
  }

  async modelMutations({ sessionId, message, brain }) {
    if (!this.complete) return [];
    const snapshot = this.store.snapshot(sessionId);
    const prompt = [
      "You are Nex Assistant controlling an Echo MCP action queue.",
      "Return only JSON: {\"mutations\":[...]}",
      "Allowed mutation types: update_action, delete_action, replace_action, dispatch_action, add_note_context.",
      "Do not hardcode capabilities. Reason from the queue state and the user's natural language.",
      "",
      `Queue state:\n${JSON.stringify(snapshot.actions, null, 2)}`,
      `User request:\n${message}`
    ].join("\n");
    try {
      const completion = await this.complete(prompt, brain);
      const candidate = completion.match(/\{[\s\S]*\}/)?.[0] ?? completion;
      const parsed = JSON.parse(candidate);
      return Array.isArray(parsed.mutations) ? parsed.mutations : [];
    } catch {
      return [];
    }
  }

  applyMutations(sessionId, mutations) {
    const applied = [];
    for (const mutation of mutations) {
      if (mutation.type === "update_action") {
        const updated = this.store.updateAction(mutation.actionId, mutation.patch ?? {}, { sessionId });
        if (updated) applied.push({ ...mutation, action: updated });
      } else if (mutation.type === "delete_action") {
        const updated = this.store.cancelAction(mutation.actionId, { sessionId, reason: mutation.reason ?? "Canceled by Nex Assistant" });
        if (updated) {
          this.spawner?.cancel?.(mutation.actionId, sessionId);
          applied.push({ ...mutation, action: updated });
        }
      } else if (mutation.type === "replace_action") {
        const replacements = (mutation.actions ?? []).map((action) => normalizeAction({ ...action, id: action.id ?? crypto.randomUUID(), sessionId }));
        const actions = this.store.replaceAction(mutation.actionId, replacements, { sessionId });
        if (actions) applied.push({ ...mutation, actions: replacements });
      } else if (mutation.type === "dispatch_action") {
        const action = this.store.upsertAction({ ...mutation.action, status: "pending" }, { sessionId });
        this.spawner?.spawn?.(action);
        applied.push({ ...mutation, action });
      } else if (mutation.type === "add_note_context") {
        applied.push(mutation);
      }
    }
    return applied;
  }
}

export function inferQueueMutations(snapshot, message) {
  const lower = message.toLowerCase();
  const actions = snapshot.actions ?? [];
  if (/\b(cancel|don't|do not|stop)\b/.test(lower)) {
    const target = findTarget(actions, lower);
    return target ? [{ type: "delete_action", actionId: target.id, reason: message }] : [];
  }

  const time = message.match(/\b\d{1,2}(?::\d{2})?\s*(am|pm)\b/i)?.[0];
  if (time && /\b(change|move|actually|make)\b/.test(lower)) {
    const target = findTarget(actions, "calendar") ?? actions.find((action) => action.tool === "calendar_create_event");
    if (target) {
      return [{
        type: "update_action",
        actionId: target.id,
        patch: {
          status: "pending",
          params: { ...target.params, when: rewriteTime(target.params?.when, time) },
          summary: `${target.summary} Updated to ${time}.`
        }
      }];
    }
  }

  if (/\bsplit\b/.test(lower) && /\bnotion|notes|page/.test(lower)) {
    const target = findTarget(actions, "notion") ?? actions.find((action) => action.tool?.startsWith("notion_"));
    if (!target) return [];
    const baseContent = target.params?.content ?? snapshot.transcript ?? "";
    return [{
      type: "replace_action",
      actionId: target.id,
      actions: [
        {
          type: "mcp_action",
          tool: "notion_create_page",
          params: { title: "Design notes", content: filterContext(baseContent, "design") },
          confidence: Math.max(target.confidence ?? 0.8, 0.82),
          source_quote: message
        },
        {
          type: "mcp_action",
          tool: "notion_create_page",
          params: { title: "Engineering notes", content: filterContext(baseContent, "engineering") },
          confidence: Math.max(target.confidence ?? 0.8, 0.82),
          source_quote: message
        }
      ]
    }];
  }

  if (/\b(add|include|remember)\b/.test(lower) && /\bcontext|note|notes\b/.test(lower)) {
    return [{ type: "add_note_context", text: message }];
  }

  return [];
}

function findTarget(actions, lower) {
  if (lower.includes("email")) return actions.find((action) => action.tool?.startsWith("gmail_"));
  if (lower.includes("calendar") || lower.includes("event")) return actions.find((action) => action.tool === "calendar_create_event");
  if (lower.includes("notion") || lower.includes("notes")) return actions.find((action) => action.tool?.startsWith("notion_"));
  return actions.find((action) => ["running", "pending", "suggested"].includes(action.status));
}

function rewriteTime(existing, time) {
  const source = String(existing ?? "").trim();
  if (!source) return time;
  if (/\b\d{1,2}(?::\d{2})?\s*(am|pm)\b/i.test(source)) {
    return source.replace(/\b\d{1,2}(?::\d{2})?\s*(am|pm)\b/i, time);
  }
  return `${source} ${time}`.trim();
}

function filterContext(content, keyword) {
  const sentences = String(content ?? "").split(/(?<=[.!?])\s+/).filter(Boolean);
  const matching = sentences.filter((sentence) => sentence.toLowerCase().includes(keyword));
  return (matching.length ? matching : sentences).join(" ");
}
