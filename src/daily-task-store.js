import fs from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";

const STORE_PATH = process.env.NEXUS_DAILY_TASK_STORE ?? path.join(process.cwd(), ".nexus-data", "daily-tasks.sqlite");
fs.mkdirSync(path.dirname(STORE_PATH), { recursive: true });

const database = new Database(STORE_PATH);
database.pragma("journal_mode = WAL");
database.exec(`
  CREATE TABLE IF NOT EXISTS daily_tasks (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    status TEXT NOT NULL,
    day_key TEXT NOT NULL,
    sort_order INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    completed_at TEXT
  );
  CREATE TABLE IF NOT EXISTS daily_task_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
`);

const selectTasks = database.prepare("SELECT * FROM daily_tasks WHERE day_key = ? ORDER BY status = 'done', sort_order ASC, created_at ASC");
const insertTask = database.prepare(`
  INSERT INTO daily_tasks (id, title, status, day_key, sort_order, created_at, completed_at)
  VALUES (@id, @title, 'todo', @dayKey, @sortOrder, @createdAt, NULL)
`);
const updateStatus = database.prepare("UPDATE daily_tasks SET status = @status, sort_order = @sortOrder, completed_at = @completedAt WHERE id = @id AND day_key = @dayKey");
const deleteForDay = database.prepare("DELETE FROM daily_tasks WHERE day_key = ?");
const getMeta = database.prepare("SELECT value FROM daily_task_meta WHERE key = ?");
const setMeta = database.prepare(`
  INSERT INTO daily_task_meta (key, value) VALUES (@key, @value)
  ON CONFLICT(key) DO UPDATE SET value = excluded.value
`);

export async function listDailyTasks({ now = new Date() } = {}) {
  resetAtMidnightIfNeeded(now);
  return snapshot(now);
}

export async function addDailyTask(title, { now = new Date() } = {}) {
  resetAtMidnightIfNeeded(now);
  const trimmed = String(title ?? "").trim();
  if (!trimmed) throw new Error("task title is required");
  const dayKey = localDayKey(now);
  insertTask.run({
    id: `daily-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`,
    title: trimmed,
    dayKey,
    sortOrder: Date.now(),
    createdAt: now.toISOString()
  });
  return snapshot(now);
}

export async function toggleDailyTask(id, { now = new Date() } = {}) {
  resetAtMidnightIfNeeded(now);
  const dayKey = localDayKey(now);
  const tasks = selectTasks.all(dayKey);
  const task = tasks.find((candidate) => candidate.id === id);
  if (!task) throw new Error("daily task not found");
  const nextDone = task.status !== "done";
  updateStatus.run({
    id,
    dayKey,
    status: nextDone ? "done" : "todo",
    sortOrder: nextDone ? Date.now() : 0,
    completedAt: nextDone ? now.toISOString() : null
  });
  return snapshot(now);
}

export async function resetDailyTasks({ now = new Date(), hard = true } = {}) {
  deleteForDay.run(localDayKey(now));
  if (hard) setMeta.run({ key: "last_reset_day", value: localDayKey(now) });
  return snapshot(now);
}

function resetAtMidnightIfNeeded(now) {
  const today = localDayKey(now);
  const lastReset = getMeta.get("last_reset_day")?.value;
  if (lastReset !== today) {
    deleteForDay.run(today);
    setMeta.run({ key: "last_reset_day", value: today });
  }
}

function snapshot(now) {
  const dayKey = localDayKey(now);
  return {
    dayKey,
    resetsAt: nextMidnight(now).toISOString(),
    tasks: selectTasks.all(dayKey).map(fromRecord)
  };
}

function fromRecord(record) {
  return {
    id: record.id,
    title: record.title,
    status: record.status,
    dayKey: record.day_key,
    createdAt: record.created_at,
    completedAt: record.completed_at
  };
}

function localDayKey(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function nextMidnight(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1);
}
