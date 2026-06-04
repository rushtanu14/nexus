export async function runNotionPet(action, { signal, progress } = {}) {
  progress?.("loading notion pet");
  const petdex = await optionalPetdex();
  if (petdex?.spawn) {
    const pet = petdex.spawn("notion", action.params);
    wirePetProgress(pet, progress);
    return pet.run ? pet.run({ signal }) : pet;
  }
  if (signal?.aborted) throw new Error("notion pet canceled");
  progress?.("prepared notion MCP payload");
  return { ok: true, tool: action.tool, package: "petdex notion", params: action.params };
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
