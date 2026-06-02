import fs from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";

const STORE_PATH = process.env.NEXUS_NODE_STORE ?? path.join(process.cwd(), ".nexus-data", "nodes.sqlite");
fs.mkdirSync(path.dirname(STORE_PATH), { recursive: true });

const database = new Database(STORE_PATH);
database.pragma("journal_mode = WAL");
database.exec(`
  CREATE TABLE IF NOT EXISTS nodes (
    id TEXT PRIMARY KEY,
    intent TEXT NOT NULL,
    node_json TEXT NOT NULL,
    embedding_json TEXT
  )
`);
if (!database.prepare("PRAGMA table_info(nodes)").all().some((column) => column.name === "embedding_json")) {
  database.exec("ALTER TABLE nodes ADD COLUMN embedding_json TEXT");
}

const upsertNode = database.prepare(`
  INSERT INTO nodes (id, intent, node_json, embedding_json)
  VALUES (@id, @intent, @node_json, @embedding_json)
  ON CONFLICT(id) DO UPDATE SET intent = excluded.intent, node_json = excluded.node_json, embedding_json = excluded.embedding_json
`);
const selectNodes = database.prepare("SELECT intent, node_json, embedding_json FROM nodes");
const deleteNodes = database.prepare("DELETE FROM nodes");
const deleteNodeByID = database.prepare("DELETE FROM nodes WHERE id = ?");

export async function saveNode(node, intent = node.meta.label) {
  const embedding = await embedIntent(intent);
  upsertNode.run({ id: node.id, intent, node_json: JSON.stringify(node), embedding_json: embedding ? JSON.stringify(embedding) : null });
}

export async function findNode(intent) {
  const intentEmbedding = await embedIntent(intent);
  let best = null;
  for (const record of selectNodes.all()) {
    const storedEmbedding = record.embedding_json ? JSON.parse(record.embedding_json) : null;
    const similarity = Math.max(
      semanticSimilarity(intent, record.intent),
      intentEmbedding && storedEmbedding ? cosineSimilarity(intentEmbedding, storedEmbedding) : 0
    );
    if (!best || similarity > best.similarity) best = { similarity, node: JSON.parse(record.node_json) };
  }
  return best?.similarity >= 0.92 ? structuredClone(best.node) : null;
}

export async function listNodes() {
  return selectNodes.all().map((record) => JSON.parse(record.node_json));
}

export async function clearNodes() {
  deleteNodes.run();
}

export async function deleteNode(id) {
  deleteNodeByID.run(id);
}

function semanticSimilarity(left, right) {
  const a = normalizeIntent(left);
  const b = normalizeIntent(right);
  if (a === b) return 1;
  const leftTokens = new Set(a.split(" "));
  const rightTokens = new Set(b.split(" "));
  const intersection = [...leftTokens].filter((token) => rightTokens.has(token)).length;
  const union = new Set([...leftTokens, ...rightTokens]).size;
  const jaccard = union ? intersection / union : 0;
  return jaccard;
}

function normalizeIntent(intent) {
  const synonyms = new Map([
    ["send", "request"], ["post", "request"], ["get", "request"], ["data", "body"],
    ["webhook", "url"], ["file", "path"], ["page", "browser"], ["go", "open"],
    ["navigate", "open"], ["read", "extract"], ["text", "value"]
  ]);
  const stopWords = new Set(["a", "an", "the", "to", "at", "http", "body"]);
  const tokens = String(intent).toLowerCase().match(/[a-z0-9]+/g)?.map((token) => synonyms.get(token) ?? token).filter((token) => !stopWords.has(token)) ?? [];
  return [...new Set(tokens)].sort().join(" ");
}

async function embedIntent(intent) {
  if (process.env.NEXUS_USE_OLLAMA_EMBEDDINGS === "0") return null;
  try {
    const baseUrl = process.env.OLLAMA_BASE_URL ?? "http://127.0.0.1:11434";
    const response = await fetch(`${baseUrl}/api/embeddings`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ model: "nomic-embed-text", prompt: intent }),
      signal: AbortSignal.timeout(300)
    });
    if (!response.ok) return null;
    return (await response.json()).embedding ?? null;
  } catch {
    return null;
  }
}

function cosineSimilarity(left, right) {
  if (left.length !== right.length || left.length === 0) return 0;
  let dot = 0;
  let leftMagnitude = 0;
  let rightMagnitude = 0;
  for (let index = 0; index < left.length; index += 1) {
    dot += left[index] * right[index];
    leftMagnitude += left[index] ** 2;
    rightMagnitude += right[index] ** 2;
  }
  return dot / (Math.sqrt(leftMagnitude) * Math.sqrt(rightMagnitude));
}
