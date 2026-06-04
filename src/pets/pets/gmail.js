export async function runGmailPet(action, { signal, progress } = {}) {
  progress?.("loading gmail pet");
  const petdex = await optionalPetdex();
  if (petdex?.spawn) {
    const pet = petdex.spawn("gmail", action.params);
    wirePetProgress(pet, progress);
    return pet.run ? pet.run({ signal }) : pet;
  }
  if (signal?.aborted) throw new Error("gmail pet canceled");
  progress?.("prepared gmail MCP payload");
  return { ok: true, tool: action.tool, package: "petdex gmail", params: action.params };
}

async function optionalPetdex() {
  try {
    return await import("petdex");
  } catch {
    return null;
  }
}

function wirePetProgress(pet, progress) {
  if (!pet?.on || !progress) return;
  pet.on("pet:progress", progress);
}
