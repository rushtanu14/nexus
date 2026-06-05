import { exec, execFile } from "node:child_process";
import fs from "node:fs/promises";
import { promisify } from "node:util";
import { callRegisteredTool, resolveServer } from "../mcp-registry.js";

const execAsync = promisify(exec);
const execFileAsync = promisify(execFile);
const adapters = {
  browser: null,
  mcp: null,
  ai: null
};

let currentPage = { url: null, html: "" };

export function configureRunners(nextAdapters = {}) {
  Object.assign(adapters, nextAdapters);
}

export function resetRunners() {
  adapters.browser = null;
  adapters.mcp = null;
  adapters.ai = null;
  currentPage = { url: null, html: "" };
}

async function browserGoto({ url }) {
  if (adapters.browser?.goto) return adapters.browser.goto(url);
  const normalizedUrl = /^[a-z]+:\/\//i.test(url) ? url : `https://${url}`;
  const response = await fetch(normalizedUrl);
  if (!response.ok) throw new Error(`browser_goto failed with HTTP ${response.status}`);
  currentPage = { url: normalizedUrl, html: await response.text() };
  if (process.platform === "darwin" && process.env.NEXUS_BROWSER_VISIBLE !== "0") {
    await execFileAsync("/usr/bin/open", [normalizedUrl]);
  }
  return { url: normalizedUrl, opened: process.platform === "darwin" && process.env.NEXUS_BROWSER_VISIBLE !== "0" };
}

async function browserExtract({ selector, attribute }) {
  if (adapters.browser?.extract) return adapters.browser.extract(selector, attribute);
  const html = currentPage.html;
  if (!html) throw new Error("browser_extract requires browser_goto first");
  const element = findElement(html, selector);
  if (!element) throw new Error(`selector not found: ${selector}`);
  if (attribute === "innerText" || attribute === "textContent") return stripTags(element.content).trim();
  const match = element.openingTag.match(new RegExp(`\\s${escapeRegExp(attribute)}=(?:"([^"]*)"|'([^']*)')`, "i"));
  return match?.[1] ?? match?.[2] ?? null;
}

async function browserClick({ selector }) {
  if (!adapters.browser?.click) throw new Error("browser_click requires a configured browser adapter");
  return adapters.browser.click(selector);
}

async function browserFill({ selector, value }) {
  if (!adapters.browser?.fill) throw new Error("browser_fill requires a configured browser adapter");
  return adapters.browser.fill(selector, value);
}

async function shellRun({ command }) {
  try {
    const { stdout, stderr } = await execAsync(command);
    return { stdout, stderr, code: 0 };
  } catch (error) {
    return { stdout: error.stdout ?? "", stderr: error.stderr ?? error.message, code: error.code ?? 1 };
  }
}

async function httpRequest({ url, method, body }) {
  const options = { method };
  if (body !== undefined && body !== "") {
    options.body = typeof body === "string" ? body : JSON.stringify(body);
    options.headers = { "content-type": "application/json" };
  }
  const response = await fetch(url, options);
  const text = await response.text();
  let data = text;
  try {
    data = JSON.parse(text);
  } catch {
    // Preserve non-JSON response bodies as strings.
  }
  return { status: response.status, data };
}

async function mcpCall({ server, tool, inputs }) {
  if (adapters.mcp?.call) return adapters.mcp.call(server, tool, inputs);
  const registered = resolveServer(server);
  if (registered) return callRegisteredTool(server, tool, inputs);
  const response = await fetch(server, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: crypto.randomUUID(), method: "tools/call", params: { name: tool, arguments: inputs } })
  });
  if (!response.ok) throw new Error(`mcp_call failed with HTTP ${response.status}`);
  const payload = await response.json();
  if (payload.error) throw new Error(payload.error.message ?? "MCP call failed");
  return payload.result;
}

async function aiInfer({ prompt, context }) {
  if (!adapters.ai?.infer) throw new Error("ai_infer requires a configured AI adapter");
  return adapters.ai.infer(prompt, context);
}

export const RUNNERS = {
  browser_goto: browserGoto,
  browser_extract: browserExtract,
  browser_click: browserClick,
  browser_fill: browserFill,
  fs_read: ({ path }) => fs.readFile(path, "utf8"),
  fs_write: ({ path, content }) => fs.writeFile(path, content, "utf8"),
  shell_run: shellRun,
  http_request: httpRequest,
  mcp_call: mcpCall,
  ai_infer: aiInfer
};

function findElement(html, selector) {
  if (selector === "title") return matchTag(html, "title");
  if (/^[a-z][\w-]*$/i.test(selector)) return matchTag(html, selector);
  if (selector.startsWith(".")) return matchAttribute(html, "class", selector.slice(1), true);
  if (selector.startsWith("#")) return matchAttribute(html, "id", selector.slice(1), false);
  throw new Error(`fallback browser_extract only supports tag, .class, and #id selectors: ${selector}`);
}

function matchTag(html, tag) {
  const match = html.match(new RegExp(`<(${escapeRegExp(tag)})\\b[^>]*>([\\s\\S]*?)<\\/\\1>`, "i"));
  return match && { openingTag: match[0].slice(0, match[0].indexOf(">") + 1), content: match[2] };
}

function matchAttribute(html, attribute, value, isToken) {
  const pattern = isToken ? `(?:^|\\s)${escapeRegExp(value)}(?:\\s|$)` : `^${escapeRegExp(value)}$`;
  const tagPattern = /<([a-z][\w-]*)\b([^>]*)>([\s\S]*?)<\/\1>/gi;
  for (const match of html.matchAll(tagPattern)) {
    const attr = match[2].match(new RegExp(`\\s${attribute}=(?:"([^"]*)"|'([^']*)')`, "i"));
    if (attr && new RegExp(pattern).test(attr[1] ?? attr[2])) {
      return { openingTag: match[0].slice(0, match[0].indexOf(">") + 1), content: match[3] };
    }
  }
  return null;
}

function stripTags(html) {
  return html.replace(/<[^>]*>/g, "").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'");
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
