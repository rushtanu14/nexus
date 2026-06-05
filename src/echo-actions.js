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

const ATTENDEE_STOP_WORDS = new Set([
  "Action",
  "Agenda",
  "Client",
  "Decision",
  "Discussion",
  "Draft",
  "Echo",
  "Friday",
  "Follow",
  "Meeting",
  "Monday",
  "Nex",
  "Next",
  "Notes",
  "Objective",
  "Owner",
  "Participants",
  "Please",
  "Product",
  "Saturday",
  "Sunday",
  "Sync",
  "Thursday",
  "Tuesday",
  "Untitled",
  "Wednesday",
  "Weekly",
  "Yeah",
  "You",
  "Your"
]);

export function buildEchoActions({ transcript = "", notes = "", title = "Echo notes", memory = "" } = {}) {
  const context = normalizeText([title, notes, transcript, memory].filter(Boolean).join("\n\n"));
  if (!context) return [];

  const actions = [];
  const wantsInvite = mentions(context, ["invite", "calendar invite", "send me over an invite", "shoot me over an invite", "meeting invite"]);
  const wantsFollowUpMeeting = mentions(context, ["sync up", "sync-up", "meet again", "follow up", "follow-up", "tomorrow", "next meeting"]);
  const wantsEmail = mentions(context, ["follow up", "follow-up", "email", "send", "shoot me", "invite"]) || mentions(context, ["client", "customer", "candidate"]);
  const wantsCalendar = wantsInvite || wantsFollowUpMeeting || mentions(context, ["schedule", "calendar", "meeting", "call", "next week"]);

  const hasFollowUpWorkflow = wantsInvite && wantsEmail;
  if (hasFollowUpWorkflow) {
    actions.push(workflowAction({
      kind: "meeting_followup_workflow",
      title: "Create invite and follow-up workflow",
      summary: "Prepare a Google Calendar invite and Gmail follow-up from the meeting context.",
      confidence: confidence(context, ["invite", "sync up", "tomorrow", "send", "follow up"]) + 0.1,
      calls: [
        {
          provider: PROVIDERS.workspace,
          payload: {
            title: subjectFor(title, "Follow-up sync"),
            attendees_hint: inferAttendees(context),
            when_hint: inferWhen(context),
            agenda: inferredTasks(context).join("\n"),
            context
          }
        },
        {
          provider: PROVIDERS.gmail,
          payload: {
            subject: subjectFor(title, "Follow-up sync"),
            to_hint: inferAttendees(context),
            body: followUpBody(context),
            context
          }
        }
      ]
    }));
  }

  if (wantsEmail && !hasFollowUpWorkflow) {
    actions.push(action({
      kind: "email_follow_up",
      provider: PROVIDERS.gmail,
      title: "Draft follow-up email",
      summary: "Prepare a concise follow-up email from the meeting context.",
      confidence: confidence(context, ["follow up", "email", "send", "client", "customer"]),
      payload: {
        subject: subjectFor(title, "Follow-up"),
        to_hint: inferAttendees(context),
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

  if (wantsCalendar && !hasFollowUpWorkflow) {
    actions.push(action({
      kind: "calendar_follow_up",
      provider: PROVIDERS.workspace,
      title: "Prepare follow-up calendar invite",
      summary: "Draft a Google Calendar follow-up invite from the call context.",
      confidence: confidence(context, ["schedule", "calendar", "meeting", "call", "next week"]),
      payload: {
        title: subjectFor(title, "Follow-up meeting"),
        attendees_hint: inferAttendees(context),
        when_hint: inferWhen(context),
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
  const calls = action?.mcp?.steps?.length ? action.mcp.steps : [action?.mcp].filter(Boolean);
  const missing = calls.filter((call) => !registeredServers[call.server]).map((call) => call.server);
  if (missing.length > 0) {
    return {
      ok: false,
      status: "needs_mcp",
      message: `${action?.provider ?? "MCP"} action is ready, but these MCP servers are not registered yet: ${[...new Set(missing)].join(", ")}.`,
      action
    };
  }
  return {
    ok: true,
    status: "ready_to_run",
    message: `Prepared ${action.title} with ${calls.length} MCP step(s).`,
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

function workflowAction({ kind, title, summary, confidence, calls }) {
  const steps = calls.map(({ provider, payload }) => ({
    server: provider.server,
    tool: provider.tool,
    inputs: payload
  }));
  return {
    id: crypto.randomUUID(),
    kind,
    provider: "MCP Workflow",
    title,
    summary,
    confidence: Math.min(0.98, confidence),
    status: "suggested",
    mcp: {
      server: "workflow",
      tool: "multi_step",
      inputs: {
        summary,
        step_count: String(steps.length)
      },
      steps
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

function inferAttendees(context) {
  const ownerNames = [...context.matchAll(/\bOwner:\s*([A-Z][a-z]{2,}(?:\s+[A-Z][a-z]{2,}){0,2})/g)]
    .flatMap((match) => match[1].split(/\s+/));
  const spokenNames = [...context.matchAll(/\b[A-Z][a-z]{2,}\b/g)]
    .map((match) => match[0])
    .filter((name) => !ATTENDEE_STOP_WORDS.has(name));
  const names = [...ownerNames, ...spokenNames].filter((name) => !ATTENDEE_STOP_WORDS.has(name));
  return [...new Set(names)].slice(0, 5).join(", ") || "Infer from meeting participants and memory";
}

function inferWhen(context) {
  const lower = context.toLowerCase();
  const monthDate = context.match(/\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2},\s+\d{4}\b/i);
  if (monthDate) return monthDate[0];
  const iso = context.match(/\b\d{4}-\d{2}-\d{2}\b/);
  if (iso) return iso[0];
  if (lower.includes("tomorrow")) return "tomorrow";
  const nextWeek = context.match(/\bnext\s+(week|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/i);
  if (nextWeek) return nextWeek[0];
  const weekday = context.match(/\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/i);
  if (weekday) return weekday[0];
  return "Infer from meeting context";
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
