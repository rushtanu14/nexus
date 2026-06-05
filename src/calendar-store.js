import fs from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";
import { buildEchoActions } from "./echo-actions.js";
import { createLifePlan } from "./life-assistant.js";
import { callRegisteredTool, listServers } from "./mcp-registry.js";

const STORE_PATH = process.env.NEXUS_CALENDAR_STORE ?? path.join(process.cwd(), ".nexus-data", "calendar.sqlite");
fs.mkdirSync(path.dirname(STORE_PATH), { recursive: true });

const database = new Database(STORE_PATH);
database.pragma("journal_mode = WAL");
database.exec(`
  CREATE TABLE IF NOT EXISTS calendar_events (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    date_text TEXT NOT NULL,
    time_text TEXT NOT NULL,
    source TEXT NOT NULL,
    context TEXT NOT NULL,
    status TEXT NOT NULL,
    mcp_server TEXT NOT NULL,
    mcp_tool TEXT NOT NULL,
    created_at TEXT NOT NULL,
    result_json TEXT
  )
`);

const insertEvent = database.prepare(`
  INSERT INTO calendar_events (id, title, date_text, time_text, source, context, status, mcp_server, mcp_tool, created_at, result_json)
  VALUES (@id, @title, @dateText, @timeText, @source, @context, @status, @mcpServer, @mcpTool, @createdAt, @resultJson)
`);
const selectEvents = database.prepare("SELECT * FROM calendar_events ORDER BY created_at DESC");
const deleteEvents = database.prepare("DELETE FROM calendar_events");

export async function listCalendarEvents() {
  return selectEvents.all().map(fromRecord);
}

export async function resetCalendar() {
  deleteEvents.run();
  return { ok: true };
}

export async function inferSchedule({ transcript = "", spoken = "", connectorContext = "", title = "Nexus schedule" } = {}) {
  const connectorText = typeof connectorContext === "string" ? connectorContext : JSON.stringify(connectorContext, null, 2);
  const liveConnectorText = await connectorScheduleContext();
  const sourceText = [title, connectorText, liveConnectorText, spoken, transcript].filter(Boolean).join("\n\n");
  if (!sourceText.trim()) throw new Error("calendar context is required");
  const plan = createLifePlan(sourceText);
  const echoActions = buildEchoActions({ title, transcript, notes: [spoken, connectorText, liveConnectorText].filter(Boolean).join("\n\n") });
  const calendarActions = echoActions.filter((action) => action.mcp?.server === "google-workspace" || action.mcp?.steps?.some((step) => step.server === "google-workspace"));
  const events = [];
  if (plan.nextMeeting) {
    events.push({
      title: plan.nextMeeting.title,
      dateText: plan.nextMeeting.dateText,
      timeText: plan.nextMeeting.timeText,
      source: plan.nextMeeting.source,
      context: plan.brief
    });
  }
  for (const action of calendarActions) {
    const steps = action.mcp.steps?.length ? action.mcp.steps : [action.mcp];
    for (const step of steps.filter((candidate) => candidate.server === "google-workspace")) {
      events.push({
        title: step.inputs.title ?? step.inputs.subject ?? action.title,
        dateText: step.inputs.when_hint ?? "Date to confirm",
        timeText: step.inputs.time_hint ?? "Time to confirm",
        source: action.summary,
        context: step.inputs.context ?? plan.brief
      });
    }
  }
  return {
    title: plan.title,
    brief: plan.brief,
    tasks: plan.tasks,
    events: dedupeEvents(events).slice(0, 8),
    actions: calendarActions,
    agents: [
      { name: "memory-context-agent", status: transcript.includes("Relevant local memory") ? "used" : "available" },
      { name: "connector-sync-agent", status: liveConnectorText ? "used" : "no-registered-schedule-tools" },
      { name: "transcript-task-agent", status: `${plan.tasks.length} task(s)` },
      { name: "calendar-mcp-agent", status: `${calendarActions.length} calendar action(s)` }
    ]
  };
}

export async function createCalendarEvent(event, { autoRun = true } = {}) {
  const normalized = normalizeEvent(event);
  const servers = await listServers();
  let result = null;
  let status = servers["google-workspace"] ? "ready" : "needs_mcp";
  if (autoRun && servers["google-workspace"]) {
    result = await callRegisteredTool("google-workspace", "create_calendar_event", {
      title: normalized.title,
      date_text: normalized.dateText,
      time_text: normalized.timeText,
      source: normalized.source,
      context: normalized.context
    });
    status = "created";
  }
  insertEvent.run({
    ...normalized,
    status,
    mcpServer: "google-workspace",
    mcpTool: "create_calendar_event",
    createdAt: new Date().toISOString(),
    resultJson: result ? JSON.stringify(result) : null
  });
  return { ...normalized, status, mcp: { server: "google-workspace", tool: "create_calendar_event" }, result };
}

function normalizeEvent(event = {}) {
  const id = event.id || `calendar-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
  const title = String(event.title ?? "Nexus follow-up").trim();
  return {
    id,
    title: title || "Nexus follow-up",
    dateText: String(event.dateText ?? event.when_hint ?? event.when ?? "Date to confirm").trim() || "Date to confirm",
    timeText: String(event.timeText ?? "Time to confirm").trim() || "Time to confirm",
    source: String(event.source ?? "Inferred from Nexus context").trim(),
    context: String(event.context ?? event.details ?? "").trim()
  };
}

function dedupeEvents(events) {
  const seen = new Set();
  return events.filter((event) => {
    const key = `${event.title}|${event.dateText}|${event.timeText}`.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function fromRecord(record) {
  return {
    id: record.id,
    title: record.title,
    dateText: record.date_text,
    timeText: record.time_text,
    source: record.source,
    context: record.context,
    status: record.status,
    mcp: { server: record.mcp_server, tool: record.mcp_tool },
    createdAt: record.created_at,
    result: record.result_json ? JSON.parse(record.result_json) : null
  };
}

async function connectorScheduleContext() {
  const servers = await listServers();
  const probes = [
    ["google-workspace", "list_calendar_events", { range: "upcoming" }],
    ["notion", "list_tasks", { status: "open" }],
    ["google-drive", "search_docs", { query: "meeting notes action items" }]
  ].filter(([server]) => servers[server]);
  const sections = [];
  for (const [server, tool, inputs] of probes) {
    try {
      const result = await callRegisteredTool(server, tool, inputs);
      sections.push(`${server}/${tool}:\n${JSON.stringify(result, null, 2)}`);
    } catch {
      // Connector sync is opportunistic; unavailable optional tools should not block schedule inference.
    }
  }
  return sections.join("\n\n");
}
