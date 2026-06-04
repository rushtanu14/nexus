import { runWithPetPackageOrMcp } from "./mcp-executor.js";

export async function runGcalPet(action, { signal, progress } = {}) {
  return runWithPetPackageOrMcp({
    packageNames: ["Agumon", "agumon"],
    mcpServerNames: ["google-workspace", "gcal", "google-calendar"],
    action,
    signal,
    progress,
    authLabel: "Google Calendar"
  });
}
