import { runWithPetPackageOrMcp } from "./mcp-executor.js";

export async function runNotionPet(action, { signal, progress } = {}) {
  return runWithPetPackageOrMcp({
    packageNames: ["aqua-wisp"],
    mcpServerNames: ["notion"],
    action,
    signal,
    progress,
    authLabel: "Notion"
  });
}
