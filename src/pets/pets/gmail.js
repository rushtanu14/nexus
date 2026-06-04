import { runWithPetPackageOrMcp } from "./mcp-executor.js";

export async function runGmailPet(action, { signal, progress } = {}) {
  return runWithPetPackageOrMcp({
    packageNames: ["77"],
    mcpServerNames: ["gmail"],
    action,
    signal,
    progress,
    authLabel: "Gmail"
  });
}
