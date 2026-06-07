#!/usr/bin/env node
import { BRIDGES } from "./nexus-mcp-bridge.mjs";

const ENGINE_URL = (process.env.NEXUS_ENGINE_URL ?? "http://127.0.0.1:3131").replace(/\/$/, "");
const HOST = process.env.NEXUS_MCP_HOST ?? "127.0.0.1";

function selectedApps(argv) {
  const onlyIndex = argv.findIndex((arg) => arg === "--only" || arg === "--apps");
  const selected = onlyIndex >= 0 ? argv[onlyIndex + 1] : process.env.NEXUS_MCP_APPS;
  if (!selected) return Object.keys(BRIDGES);
  return selected.split(",").map((item) => item.trim()).filter(Boolean);
}

for (const app of selectedApps(process.argv.slice(2))) {
  const bridge = BRIDGES[app];
  if (!bridge) throw new Error(`Unknown MCP bridge app: ${app}`);
  const url = `http://${HOST}:${bridge.port}`;
  const response = await fetch(`${ENGINE_URL}/mcp/register`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ app, url, project: "nexus" })
  });
  const payload = await response.json();
  if (!response.ok || payload.error) {
    throw new Error(`${app} registration failed: ${payload.error ?? response.status}`);
  }
  console.log(`${app} registered at ${url} (${payload.found} tool${payload.found === 1 ? "" : "s"})`);
}
