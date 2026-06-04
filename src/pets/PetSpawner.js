import { EventEmitter } from "node:events";
import { actionStore } from "../store/ActionStore.js";
import { runGcalPet } from "./pets/gcal.js";
import { runGmailPet } from "./pets/gmail.js";
import { runNotionPet } from "./pets/notion.js";

const PET_RUNNERS = {
  "77": runGmailPet,
  "aqua-wisp": runNotionPet,
  Agumon: runGcalPet,
  gcal: runGcalPet,
  gmail: runGmailPet,
  notion: runNotionPet
};

export class PetSpawner extends EventEmitter {
  constructor({ store = actionStore } = {}) {
    super();
    this.store = store;
    this.running = new Map();
  }

  spawn(action) {
    const petName = action.pet ?? petForTool(action.tool);
    const run = PET_RUNNERS[petName] ?? runGenericPet;
    const controller = new AbortController();
    this.running.set(action.id, controller);
    this.store.updateAction(action.id, { status: "running", pet: petName }, { sessionId: action.sessionId });
    this.emit("pet:progress", { actionId: action.id, pet: petName, message: "started" });

    void run(action, {
      signal: controller.signal,
      progress: (message) => {
        this.emit("pet:progress", { actionId: action.id, pet: petName, message });
        this.store.updateAction(action.id, { progress: message }, { sessionId: action.sessionId });
      }
    }).then((result) => {
      if (controller.signal.aborted) return;
      this.running.delete(action.id);
      this.store.updateAction(action.id, { status: "done", result }, { sessionId: action.sessionId });
      this.emit("pet:done", { actionId: action.id, pet: petName, result });
    }).catch((error) => {
      this.running.delete(action.id);
      const status = controller.signal.aborted ? "canceled" : "error";
      this.store.updateAction(action.id, { status, error: error.message }, { sessionId: action.sessionId });
      this.emit("pet:error", { actionId: action.id, pet: petName, error });
    });

    return { id: action.id, pet: petName, cancel: () => this.cancel(action.id, action.sessionId) };
  }

  cancel(actionId, sessionId) {
    const controller = this.running.get(actionId);
    if (controller) controller.abort();
    this.running.delete(actionId);
    return this.store.cancelAction(actionId, { sessionId, reason: "Canceled while pet was running" });
  }
}

async function runGenericPet(action, { progress }) {
  progress?.("checking MCP authentication");
  throw new Error(`No pet package or authenticated MCP runner is configured for ${action.tool}.`);
}

function petForTool(tool) {
  if (tool.startsWith("calendar_") || tool.startsWith("gcal_") || tool === "create_calendar_event") return "Agumon";
  if (tool.startsWith("gmail_") || tool === "draft_email") return "77";
  if (tool.startsWith("notion_") || tool === "create_tasks") return "aqua-wisp";
  return "mcp";
}
