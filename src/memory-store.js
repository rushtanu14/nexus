import crypto from "node:crypto";

export const REQUIRED_MEMORY_PAYLOAD_FIELDS = [
  "memory_type",
  "content",
  "timestamp",
  "source",
  "importance",
  "project",
  "tags"
];

export const LOCAL_MEMORY_EMBEDDING_MODEL = "nexus-local-hash-v1";

const DEFAULT_COLLECTION = "nexus_memories_v1";
const DEFAULT_QDRANT_URL = "http://127.0.0.1:6333";
const DEFAULT_VECTOR_SIZE = 64;
const DEFAULT_TIMEOUT_MS = 350;
const DEFAULT_DUPLICATE_THRESHOLD = 0.985;

const PAYLOAD_INDEXES = [
  ["memory_type", "keyword"],
  ["project", "keyword"],
  ["source", "keyword"],
  ["tags", "keyword"],
  ["timestamp", "datetime"],
  ["importance", "float"],
  ["content_hash", "keyword"]
];

export function createMemoryStore(options = {}) {
  const config = memoryConfig(options);
  return {
    config,
    health: () => memoryHealth(config),
    ensureCollection: () => ensureMemoryCollection(config),
    remember: (memory, rememberOptions = {}) => rememberMemory(memory, config, rememberOptions),
    query: (text, queryOptions = {}) => queryMemories(text, config, queryOptions),
    contextForRequest: (text, queryOptions = {}) => memoryContextForRequest(text, config, queryOptions)
  };
}

export async function memoryHealth(options = {}) {
  const config = toMemoryConfig(options);
  if (config.enabled === false) {
    return { ok: false, enabled: false, url: config.url ?? DEFAULT_QDRANT_URL, reason: "memory_disabled" };
  }
  try {
    const { status } = await qdrantRequest(config, "/", { timeoutMs: config.timeoutMs });
    return {
      ok: status >= 200 && status < 300,
      enabled: true,
      url: config.url,
      dashboard: `${config.url}/dashboard`,
      grpc: config.grpcUrl,
      status
    };
  } catch (error) {
    return { ok: false, enabled: true, url: config.url, dashboard: `${config.url}/dashboard`, grpc: config.grpcUrl, error: error.message };
  }
}

export async function ensureMemoryCollection(options = {}) {
  const config = toMemoryConfig(options);
  if (config.enabled === false) return { ok: false, enabled: false, collection: config.collectionName, created: false };

  const existing = await qdrantRequest(config, `/collections/${encodeURIComponent(config.collectionName)}`, { allow404: true });
  let created = false;
  if (existing.status === 404) {
    await qdrantRequest(config, `/collections/${encodeURIComponent(config.collectionName)}`, {
      method: "PUT",
      body: { vectors: { size: config.vectorSize, distance: "Cosine" } }
    });
    created = true;
  }

  const indexes = [];
  for (const [field_name, field_schema] of PAYLOAD_INDEXES) {
    try {
      await qdrantRequest(config, `/collections/${encodeURIComponent(config.collectionName)}/index`, {
        method: "PUT",
        body: { field_name, field_schema }
      });
      indexes.push({ field: field_name, status: "ok" });
    } catch (error) {
      indexes.push({ field: field_name, status: "skipped", error: error.message });
    }
  }

  return {
    ok: true,
    enabled: true,
    collection: config.collectionName,
    created,
    vector_size: config.vectorSize,
    distance: "Cosine",
    indexes
  };
}

export async function rememberMemory(memory, options = {}, rememberOptions = {}) {
  const config = toMemoryConfig(options);
  if (config.enabled === false) return { ok: false, enabled: false, duplicate: false, reason: "memory_disabled" };

  await ensureMemoryCollection(config);
  const payload = normalizeMemoryPayload(memory, config);
  const duplicate = await findDuplicate(config, payload, rememberOptions);
  if (duplicate) {
    return {
      ok: true,
      enabled: true,
      duplicate: true,
      id: duplicate.id,
      payload: duplicate.payload,
      memory: pointToMemory(duplicate, { now: new Date(), score: duplicate.score ?? 1 })
    };
  }

  const id = memory?.id ?? crypto.randomUUID();
  const vector = embedTextLocally(payload.content, config.vectorSize);
  await qdrantRequest(config, `/collections/${encodeURIComponent(config.collectionName)}/points?wait=true`, {
    method: "PUT",
    body: { points: [{ id, vector, payload }] }
  });

  return { ok: true, enabled: true, duplicate: false, id, payload, collection: config.collectionName };
}

export async function queryMemories(text, options = {}, queryOptions = {}) {
  const config = toMemoryConfig(options);
  if (config.enabled === false) {
    return { ok: false, enabled: false, memories: [], reason: "memory_disabled", collection: config.collectionName };
  }
  const queryText = String(text ?? "").trim();
  if (!queryText) return { ok: true, enabled: true, memories: [], collection: config.collectionName };

  await ensureMemoryCollection(config);
  const vector = embedTextLocally(queryText, config.vectorSize);
  const points = await searchPoints(config, vector, {
    limit: boundedLimit(queryOptions.limit, 5),
    filter: buildMemoryFilter(queryOptions)
  });
  const now = queryOptions.now ?? new Date();
  const memories = points
    .map((point) => pointToMemory(point, { now, score: point.score ?? 0 }))
    .sort((left, right) => right.rank - left.rank);

  return {
    ok: true,
    enabled: true,
    collection: config.collectionName,
    embedding_model: LOCAL_MEMORY_EMBEDDING_MODEL,
    memories
  };
}

export async function memoryContextForRequest(text, options = {}, queryOptions = {}) {
  const config = toMemoryConfig(options);
  const result = await queryMemories(text, config, queryOptions);
  return {
    ...result,
    context: formatMemoryContext(result.memories ?? [])
  };
}

export function embedTextLocally(text, vectorSize = DEFAULT_VECTOR_SIZE) {
  const size = Math.max(8, Number(vectorSize) || DEFAULT_VECTOR_SIZE);
  const vector = new Array(size).fill(0);
  const tokens = tokenize(text);
  const counts = new Map();
  for (const token of tokens.length ? tokens : ["empty"]) {
    counts.set(token, (counts.get(token) ?? 0) + 1);
  }

  for (const [token, count] of counts) {
    const hash = crypto.createHash("sha256").update(token).digest();
    const weight = 1 + Math.log(count);
    const firstIndex = hash.readUInt32BE(0) % size;
    const secondIndex = hash.readUInt32BE(4) % size;
    vector[firstIndex] += (hash[8] % 2 === 0 ? 1 : -1) * weight;
    vector[secondIndex] += (hash[9] % 2 === 0 ? 0.5 : -0.5) * weight;
  }

  const magnitude = Math.sqrt(vector.reduce((sum, value) => sum + value ** 2, 0));
  return magnitude ? vector.map((value) => value / magnitude) : vector;
}

export function formatMemoryContext(memories) {
  return memories
    .slice(0, 8)
    .map((memory, index) => {
      const payload = memory.payload ?? memory;
      const tags = Array.isArray(payload.tags) && payload.tags.length ? ` tags=${payload.tags.join(",")}` : "";
      return `[${index + 1}] ${payload.memory_type} importance=${payload.importance} project=${payload.project}${tags}: ${payload.content}`;
    })
    .join("\n");
}

function memoryConfig(options = {}) {
  const url = stripTrailingSlash(options.url ?? process.env.NEXUS_QDRANT_URL ?? DEFAULT_QDRANT_URL);
  return {
    enabled: options.enabled ?? process.env.NEXUS_MEMORY_ENABLED !== "0",
    url,
    grpcUrl: options.grpcUrl ?? process.env.NEXUS_QDRANT_GRPC_URL ?? "localhost:6334",
    apiKey: options.apiKey ?? process.env.NEXUS_QDRANT_API_KEY ?? null,
    collectionName: options.collectionName ?? process.env.NEXUS_MEMORY_COLLECTION ?? DEFAULT_COLLECTION,
    vectorSize: positiveInteger(options.vectorSize ?? process.env.NEXUS_MEMORY_VECTOR_SIZE, DEFAULT_VECTOR_SIZE),
    timeoutMs: positiveInteger(options.timeoutMs ?? process.env.NEXUS_QDRANT_TIMEOUT_MS, DEFAULT_TIMEOUT_MS),
    duplicateThreshold: numeric(options.duplicateThreshold ?? process.env.NEXUS_MEMORY_DUPLICATE_THRESHOLD, DEFAULT_DUPLICATE_THRESHOLD)
  };
}

function toMemoryConfig(options = {}) {
  return options.url && options.collectionName && options.vectorSize ? options : memoryConfig(options);
}

async function qdrantRequest(config, path, { method = "GET", body = undefined, allow404 = false, timeoutMs = config.timeoutMs } = {}) {
  const headers = { accept: "application/json" };
  if (body !== undefined) headers["content-type"] = "application/json";
  if (config.apiKey) headers["api-key"] = config.apiKey;

  const response = await fetch(`${config.url}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs)
  });
  const raw = await response.text();
  const data = raw ? parseJson(raw) : null;
  if (!response.ok && !(allow404 && response.status === 404)) {
    throw new Error(`Qdrant ${method} ${path} failed with HTTP ${response.status}: ${short(raw)}`);
  }
  return { status: response.status, data };
}

function normalizeMemoryPayload(memory, config) {
  const content = String(memory?.content ?? "").normalize("NFKC").trim();
  if (!content) throw new Error("memory content is required");

  const memory_type = cleanToken(memory.memory_type ?? memory.memoryType ?? "prior_conversation") || "prior_conversation";
  const source = cleanToken(memory.source ?? "nexus") || "nexus";
  const project = cleanToken(memory.project ?? "nexus") || "nexus";
  const timestamp = normalizeTimestamp(memory.timestamp);
  const tags = normalizeTags(memory.tags);
  const importance = normalizeImportance(memory.importance);
  const content_hash = hashMemory({ content, memory_type, source, project });

  return {
    memory_type,
    content,
    timestamp,
    source,
    importance,
    project,
    tags,
    content_hash,
    embedding_model: LOCAL_MEMORY_EMBEDDING_MODEL,
    schema_version: 1,
    vector_size: config.vectorSize
  };
}

async function findDuplicate(config, payload, rememberOptions) {
  const exact = await scrollPoints(config, {
    limit: 1,
    filter: buildExactFilter("content_hash", payload.content_hash),
    with_payload: true,
    with_vector: false
  });
  if (exact[0]) return exact[0];

  const threshold = numeric(rememberOptions.duplicateThreshold ?? config.duplicateThreshold, DEFAULT_DUPLICATE_THRESHOLD);
  if (threshold >= 1) return null;
  const candidates = await searchPoints(config, embedTextLocally(payload.content, config.vectorSize), {
    limit: 3,
    filter: buildMemoryFilter({ project: payload.project, memory_type: payload.memory_type })
  });
  return candidates.find((point) => Number(point.score ?? 0) >= threshold) ?? null;
}

async function searchPoints(config, vector, { limit, filter } = {}) {
  const body = {
    vector,
    limit: boundedLimit(limit, 5),
    with_payload: true,
    with_vector: false
  };
  if (filter) body.filter = filter;
  const { data } = await qdrantRequest(config, `/collections/${encodeURIComponent(config.collectionName)}/points/search`, {
    method: "POST",
    body
  });
  return Array.isArray(data?.result) ? data.result : data?.result?.points ?? [];
}

async function scrollPoints(config, body) {
  const { data } = await qdrantRequest(config, `/collections/${encodeURIComponent(config.collectionName)}/points/scroll`, {
    method: "POST",
    body
  });
  return Array.isArray(data?.result) ? data.result : data?.result?.points ?? [];
}

function pointToMemory(point, { now, score }) {
  const payload = point.payload ?? {};
  const similarity = clamp(Number(score) || 0, 0, 1);
  const importance = normalizeImportance(payload.importance);
  const recency = recencyScore(payload.timestamp, now);
  const rank = similarity * 0.7 + importance * 0.2 + recency * 0.1;
  return {
    id: point.id,
    score: similarity,
    recency,
    importance,
    rank,
    payload
  };
}

function buildMemoryFilter({ project, memory_type, memoryType, source, tags } = {}) {
  const must = [];
  if (project) must.push(matchValue("project", cleanToken(project)));
  if (memory_type || memoryType) must.push(matchValue("memory_type", cleanToken(memory_type ?? memoryType)));
  if (source) must.push(matchValue("source", cleanToken(source)));
  const normalizedTags = normalizeTags(tags);
  if (normalizedTags.length === 1) must.push(matchValue("tags", normalizedTags[0]));
  if (normalizedTags.length > 1) must.push({ key: "tags", match: { any: normalizedTags } });
  return must.length ? { must } : undefined;
}

function buildExactFilter(key, value) {
  return { must: [matchValue(key, value)] };
}

function matchValue(key, value) {
  return { key, match: { value } };
}

function normalizeTags(tags) {
  const values = Array.isArray(tags) ? tags : String(tags ?? "").split(",");
  return [...new Set(values.map((tag) => cleanToken(tag)).filter(Boolean))].slice(0, 24);
}

function normalizeImportance(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0.5;
  if (parsed > 1 && parsed <= 5) return clamp(parsed / 5, 0, 1);
  return clamp(parsed, 0, 1);
}

function normalizeTimestamp(value) {
  const date = value ? new Date(value) : new Date();
  return Number.isNaN(date.getTime()) ? new Date().toISOString() : date.toISOString();
}

function recencyScore(timestamp, now = new Date()) {
  const created = new Date(timestamp).getTime();
  const current = new Date(now).getTime();
  if (!Number.isFinite(created) || !Number.isFinite(current)) return 0;
  const ageDays = Math.max(0, (current - created) / 86400000);
  return Math.exp(-ageDays / 30);
}

function hashMemory({ content, memory_type, source, project }) {
  return crypto
    .createHash("sha256")
    .update([memory_type, project, source, canonicalContent(content)].join("\n"))
    .digest("hex");
}

function canonicalContent(content) {
  return String(content).toLowerCase().replace(/\s+/g, " ").trim();
}

function tokenize(text) {
  return canonicalContent(text).match(/[a-z0-9]+/g) ?? [];
}

function cleanToken(value) {
  return String(value ?? "")
    .normalize("NFKC")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_.:-]+/g, "-")
    .replace(/^-|-$/g, "");
}

function boundedLimit(value, fallback) {
  return clamp(positiveInteger(value, fallback), 1, 50);
}

function positiveInteger(value, fallback) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function numeric(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function stripTrailingSlash(value) {
  return String(value || DEFAULT_QDRANT_URL).replace(/\/+$/, "");
}

function parseJson(raw) {
  try {
    return JSON.parse(raw);
  } catch {
    return raw;
  }
}

function short(value, max = 240) {
  const text = String(value ?? "");
  return text.length > max ? `${text.slice(0, max - 3)}...` : text;
}
