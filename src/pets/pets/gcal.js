export async function runGcalPet(action, { signal, progress } = {}) {
  progress?.("loading gcal pet");
  const petdex = await optionalPetdex();
  if (petdex?.spawn) {
    const pet = petdex.spawn("gcal", action.params);
    wirePetProgress(pet, progress);
    return pet.run ? pet.run({ signal }) : pet;
  }
  if (signal?.aborted) throw new Error("gcal pet canceled");
  progress?.("prepared calendar MCP payload");
  return { ok: true, tool: action.tool, package: "petdex gcal", params: action.params };
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
