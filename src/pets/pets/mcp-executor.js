import crypto from "node:crypto";
import { callRegisteredTool, listServers } from "../../mcp-registry.js";

export async function runWithPetPackageOrMcp({ packageNames, mcpServerNames, action, signal, progress, authLabel }) {
  progress?.(`loading ${packageNames[0]} pet`);
  const petPackage = await firstImport(packageNames);
  if (petPackage?.spawn) {
    const pet = petPackage.spawn(action.tool, action.params);
    wirePetProgress(pet, progress);
    return pet.run ? pet.run({ signal }) : pet;
  }

  const petdex = await optionalImport("petdex");
  if (petdex?.spawn) {
    const pet = petdex.spawn(packageNames[0], action.params);
    wirePetProgress(pet, progress);
    return pet.run ? pet.run({ signal }) : pet;
  }

  if (signal?.aborted) throw new Error(`${authLabel} pet canceled`);
  const servers = await listServers();
  const serverName = mcpServerNames.find((name) => servers[name]);
  if (!serverName) {
    if (process.env.NEXUS_ALLOW_MOCK_MCP === "1") {
      progress?.(`mocked ${authLabel} MCP payload`);
      return { ok: true, mocked: true, tool: action.tool, params: action.params };
    }
    throw new Error(`${authLabel} is not authenticated. Connect or register the ${mcpServerNames.join(" or ")} MCP server before dispatching this action.`);
  }

  progress?.(`calling ${serverName} MCP`);
  return callRegisteredTool(serverName, action.mcp?.tool ?? action.tool, action.params ?? action.mcp?.inputs ?? {}, signal);
}

async function firstImport(names) {
  for (const name of names) {
    const loaded = await optionalImport(name);
    if (loaded) return loaded;
  }
  return null;
}

async function optionalImport(name) {
  try {
    return await import(name);
  } catch {
    return null;
  }
}

function wirePetProgress(pet, progress) {
  if (!pet?.on || !progress) return;
  pet.on("pet:progress", progress);
}

async function callMcpTool(serverUrl, tool, inputs, signal) {
  const response = await fetch(serverUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: crypto.randomUUID(),
      method: "tools/call",
      params: { name: tool, arguments: inputs }
    }),
    signal
  });
  if (!response.ok) throw new Error(`MCP tools/call failed with HTTP ${response.status}: ${await response.text()}`);
  const payload = await response.json();
  if (payload.error) throw new Error(payload.error.message ?? "MCP tools/call failed");
  return payload.result ?? payload;
}
