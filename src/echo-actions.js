import crypto from "node:crypto";

const PROVIDERS = {
  gmail: {
    app: "Gmail",
    server: "gmail",
    tool: "draft_email"
  },
  workspace: {
    app: "Google Workspace",
    server: "google-workspace",
    tool: "create_calendar_event"
  },
  drive: {
    app: "Google Drive",
    server: "google-drive",
    tool: "create_doc"
  },
  slack: {
    app: "Slack",
    server: "slack",
    tool: "draft_message"
  },
  notion: {
    app: "Notion",
    server: "notion",
    tool: "create_tasks"
  }
};

export function buildEchoActions({ transcript = "", notes = "", title = "Echo notes", memory = "" } = {}) {
  const context = normalizeText([title, notes, transcript, memory].filter(Boolean).join("\n\n"));
  if (!context) return [];

  const actions = [];
  if (mentions(context, ["follow up", "follow-up", "email", "send"]) || mentions(context, ["client", "customer", "candidate"])) {
    actions.push(action({
      kind: "email_follow_up",
      provider: PROVIDERS.gmail,
      title: "Draft follow-up email",
      summary: "Prepare a concise follow-up email from the meeting context.",
      confidence: confidence(context, ["follow up", "email", "send", "client", "customer"]),
      payload: {
        subject: subjectFor(title, "Follow-up"),
        body: followUpBody(context),
        context
      }
    }));
  }

  if (mentions(context, ["slack", "channel", "standup", "update", "notify"])) {
    actions.push(action({
      kind: "slack_update",
      provider: PROVIDERS.slack,
      title: "Draft Slack update",
      summary: "Create a Slack-ready update for the relevant team or channel.",
      confidence: confidence(context, ["slack", "channel", "update", "notify"]),
      payload: {
        channel_hint: channelHint(context),
        message: slackMessage(context),
        context
      }
    }));
  }

  if (mentions(context, ["task", "todo", "to do", "owner", "due", "action item", "next step"])) {
    actions.push(action({
      kind: "notion_tasks",
      provider: PROVIDERS.notion,
      title: "Create Notion action items",
      summary: "Turn inferred owners, tasks, and next steps into Notion tasks.",
      confidence: confidence(context, ["task", "todo", "owner", "due", "action item", "next step"]),
      payload: {
        database_hint: "Tasks",
        tasks: inferredTasks(context).join("\n"),
        context
      }
    }));
  }

  if (mentions(context, ["report", "recap", "summary", "notes", "doc", "document"])) {
    actions.push(action({
      kind: "drive_meeting_doc",
      provider: PROVIDERS.drive,
      title: "Create meeting recap doc",
      summary: "Create a Google Drive doc with polished notes and action items.",
      confidence: confidence(context, ["report", "recap", "summary", "notes", "doc"]),
      payload: {
        name: subjectFor(title, "Meeting recap"),
        body: notes || recapBody(context),
        context
      }
    }));
  }

  if (mentions(context, ["schedule", "calendar", "meeting", "call", "next week", "tomorrow", "follow-up meeting"])) {
    actions.push(action({
      kind: "calendar_follow_up",
      provider: PROVIDERS.workspace,
      title: "Prepare follow-up calendar invite",
      summary: "Draft a Google Calendar follow-up invite from the call context.",
      confidence: confidence(context, ["schedule", "calendar", "meeting", "call", "next week"]),
      payload: {
        title: subjectFor(title, "Follow-up meeting"),
        attendees_hint: "Infer from known meeting participants and memory",
        agenda: inferredTasks(context).join("\n"),
        context
      }
    }));
  }

  return dedupeActions(actions)
    .sort((left, right) => right.confidence - left.confidence)
    .slice(0, 8);
}

export function runEchoAction(action, { registeredServers = {} } = {}) {
  const server = action?.mcp?.server;
  const registered = server ? registeredServers[server] : undefined;
  if (!registered) {
    return {
      ok: false,
      status: "needs_mcp",
      message: `${action?.provider ?? "MCP"} action is ready, but the ${server} MCP server is not registered yet.`,
      action
    };
  }
  return {
    ok: true,
    status: "ready_to_run",
    message: `Prepared ${action.title} for ${registered}.`,
    action
  };
}

function action({ kind, provider, title, summary, confidence, payload }) {
  return {
    id: crypto.randomUUID(),
    kind,
    provider: provider.app,
    title,
    summary,
    confidence,
    status: "suggested",
    mcp: {
      server: provider.server,
      tool: provider.tool,
      inputs: payload
    }
  };
}

function normalizeText(value) {
  return String(value ?? "").trim().replace(/\s+/g, " ");
}

function mentions(text, terms) {
  const lower = text.toLowerCase();
  return terms.some((term) => lower.includes(term));
}

function confidence(text, terms) {
  const lower = text.toLowerCase();
  const hits = terms.filter((term) => lower.includes(term)).length;
  return Math.min(0.95, 0.45 + hits * 0.12);
}

function subjectFor(title, fallback) {
  const clean = normalizeText(title);
  if (!clean || clean === "Untitled Echo") return fallback;
  return `${fallback}: ${clean}`;
}

function followUpBody(context) {
  return [
    "Hi,",
    "",
    "Thanks for the conversation. Here are the main takeaways and next steps I captured:",
    "",
    ...inferredTasks(context).map((task) => `- ${task}`),
    "",
    "Best,"
  ].join("\n");
}

function slackMessage(context) {
  return [
    "Meeting update:",
    ...inferredTasks(context).slice(0, 4).map((task) => `- ${task}`)
  ].join("\n");
}

function recapBody(context) {
  return [
    "# Meeting recap",
    "",
    "## Summary",
    context,
    "",
    "## Action items",
    ...inferredTasks(context).map((task) => `- ${task}`)
  ].join("\n");
}

function channelHint(context) {
  const match = context.match(/#([A-Za-z0-9_-]+)/);
  return match?.[0] ?? "Infer from meeting context";
}

function inferredTasks(context) {
  const sentences = context.split(/(?<=[.!?])\s+/).map((item) => item.trim()).filter(Boolean);
  const candidates = sentences.filter((sentence) => mentions(sentence, ["follow", "send", "schedule", "create", "task", "todo", "next", "owner", "due", "report", "notify"]));
  const selected = (candidates.length ? candidates : sentences).slice(0, 5);
  return selected.map((sentence) => sentence.replace(/^[-*]\s*/, "")).filter(Boolean);
}

function dedupeActions(actions) {
  const seen = new Set();
  return actions.filter((item) => {
    const key = `${item.kind}:${item.title}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
