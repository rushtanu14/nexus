import { spawn } from "node:child_process";
import fs from "node:fs";

export const DEFAULT_OLLAMA_BASE_URL = process.env.OLLAMA_BASE_URL ?? "http://127.0.0.1:11434";
export const DEFAULT_OLLAMA_MODEL = process.env.OLLAMA_MODEL ?? "qwen2.5-coder:1.5b";

let ollamaProcess = null;
let cpuOnlyMode = process.env.OLLAMA_NUM_GPU === "0";

export function isMetalInitializationError(value) {
  const text = String(value ?? "");
  return /MTLLibraryErrorDomain|XPC_ERROR_CONNECTION_INVALID|ggml_metal_init|ggml_backend_metal_device_init|failed to initialize Metal|failed to allocate context/i.test(text);
}

export function ollamaBaseUrl(configuredBaseUrl) {
  const configured = String(configuredBaseUrl ?? "").trim();
  if (!configured || configured.includes("api.openai.com")) return DEFAULT_OLLAMA_BASE_URL;
  return configured.replace(/\/$/, "");
}

export function ollamaModelCandidates(preferredModel) {
  const configured = String(process.env.OLLAMA_FALLBACK_MODELS ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  return [...new Set([
    preferredModel || DEFAULT_OLLAMA_MODEL,
    ...configured,
    "qwen2.5-coder:1.5b",
    "qwen2.5-coder:7b",
    "llama3.2:3b",
    "gemma3:4b"
  ].filter(Boolean))];
}

export async function ensureOllamaReady({ baseUrl = DEFAULT_OLLAMA_BASE_URL, model = DEFAULT_OLLAMA_MODEL, timeoutMs = 30000 } = {}) {
  if (!(await isOllamaReachable(baseUrl))) startOllama({ cpuOnly: cpuOnlyMode });
  await waitForOllama(baseUrl, timeoutMs);
  await pullModelIfMissing({ baseUrl, model });
  return { ok: true, baseUrl, model, cpuOnly: cpuOnlyMode };
}

export async function ollamaChat({ baseUrl = DEFAULT_OLLAMA_BASE_URL, model, body, timeoutMs = 120000, allowCpuRetry = true }) {
  await ensureOllamaReady({ baseUrl, model, timeoutMs: Number(process.env.NEXUS_OLLAMA_START_TIMEOUT_MS ?? 30000) });
  const payload = { ...body, model };
  try {
    const response = await fetch(`${baseUrl}/api/chat`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(timeoutMs)
    });
    const text = await response.text();
    if (!response.ok) {
      if (allowCpuRetry && isMetalInitializationError(text)) {
        await restartOllamaCpuOnly(baseUrl);
        return ollamaChat({ baseUrl, model, body, timeoutMs, allowCpuRetry: false });
      }
      throw new Error(`Ollama model ${model} failed with HTTP ${response.status}: ${text}`);
    }
    return text ? JSON.parse(text) : {};
  } catch (error) {
    if (allowCpuRetry && isMetalInitializationError(error.message)) {
      await restartOllamaCpuOnly(baseUrl);
      return ollamaChat({ baseUrl, model, body, timeoutMs, allowCpuRetry: false });
    }
    throw error;
  }
}

export async function ollamaChatWithFallback({ baseUrl = DEFAULT_OLLAMA_BASE_URL, preferredModel, body, timeoutMs = 120000 }) {
  const errors = [];
  for (const model of ollamaModelCandidates(preferredModel)) {
    try {
      const payload = await ollamaChat({ baseUrl, model, body, timeoutMs });
      return { payload, model, cpuOnly: cpuOnlyMode };
    } catch (error) {
      errors.push(`${model}: ${error.message}`);
      console.error(`[nexus] local model failed; trying fallback if available: ${model}`, error);
    }
  }
  const error = new Error("Local models unavailable - check system resources");
  error.details = errors;
  throw error;
}

export async function ollamaHealthCheck({ baseUrl = DEFAULT_OLLAMA_BASE_URL, model = DEFAULT_OLLAMA_MODEL } = {}) {
  const result = await ollamaChatWithFallback({
    baseUrl,
    preferredModel: model,
    timeoutMs: Number(process.env.NEXUS_OLLAMA_HEALTH_TIMEOUT_MS ?? 30000),
    body: {
      stream: false,
      options: { num_predict: 1, temperature: 0 },
      messages: [{ role: "user", content: "ping" }]
    }
  });
  return { ok: true, model: result.model, cpuOnly: result.cpuOnly };
}

async function pullModelIfMissing({ baseUrl, model }) {
  if (process.env.NEXUS_SKIP_MODEL_PULL === "1") return;
  const tags = await fetch(`${baseUrl}/api/tags`, { signal: AbortSignal.timeout(2000) }).then((response) => response.json()).catch(() => ({}));
  const present = (tags.models ?? []).some((item) => item.name === model || item.model === model);
  if (present) return;
  const response = await fetch(`${baseUrl}/api/pull`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ model, stream: false }),
    signal: AbortSignal.timeout(Number(process.env.NEXUS_PREPARE_TIMEOUT_MS ?? 600000))
  });
  if (!response.ok) throw new Error(`Ollama could not pull ${model}: ${await response.text()}`);
}

async function restartOllamaCpuOnly(baseUrl) {
  console.warn("[nexus] Ollama Metal initialization failed; restarting CPU-only with OLLAMA_NUM_GPU=0");
  cpuOnlyMode = true;
  if (ollamaProcess) {
    ollamaProcess.kill("SIGTERM");
    ollamaProcess = null;
    await sleep(1000);
  }
  startOllama({ cpuOnly: true, force: true });
  await waitForOllama(baseUrl, Number(process.env.NEXUS_OLLAMA_START_TIMEOUT_MS ?? 30000));
}

function startOllama({ cpuOnly = false, force = false } = {}) {
  if (!force && ollamaProcess && !ollamaProcess.killed) return;
  const executable = ollamaExecutable();
  if (!executable) throw new Error("Ollama is not installed or not executable.");
  const environment = { ...process.env };
  if (cpuOnly) environment.OLLAMA_NUM_GPU = "0";
  ollamaProcess = spawn(executable, ["serve"], {
    env: environment,
    stdio: ["ignore", "ignore", "pipe"],
    detached: false
  });
  ollamaProcess.stderr?.on("data", (chunk) => {
    const text = chunk.toString("utf8");
    if (isMetalInitializationError(text)) cpuOnlyMode = true;
    if (process.env.NEXUS_DEBUG_OLLAMA === "1") process.stderr.write(text);
  });
  ollamaProcess.on("exit", () => {
    ollamaProcess = null;
  });
}

function ollamaExecutable() {
  return [
    process.env.OLLAMA_PATH,
    "/Applications/Ollama.app/Contents/Resources/ollama",
    "/opt/homebrew/bin/ollama",
    "/usr/local/bin/ollama"
  ].filter(Boolean).find((candidate) => {
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return true;
    } catch {
      return false;
    }
  }) ?? "ollama";
}

async function waitForOllama(baseUrl, timeoutMs) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    if (await isOllamaReachable(baseUrl)) return true;
    await sleep(500);
  }
  throw new Error("Ollama did not become ready within 30 seconds.");
}

async function isOllamaReachable(baseUrl) {
  try {
    const response = await fetch(`${baseUrl}/api/tags`, { signal: AbortSignal.timeout(1000) });
    return response.ok;
  } catch {
    return false;
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
