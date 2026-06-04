import { EventEmitter } from "node:events";
import { actionStore } from "../store/ActionStore.js";

export class EchoListener extends EventEmitter {
  constructor({ store = actionStore, inferrer, sessionId = "default" } = {}) {
    super();
    this.store = store;
    this.inferrer = inferrer;
    this.sessionId = sessionId;
    this.isListening = false;
  }

  start() {
    this.isListening = true;
    this.emit("echo:listening", { sessionId: this.sessionId });
  }

  stop() {
    this.isListening = false;
    this.emit("echo:stopped", { sessionId: this.sessionId });
  }

  async pushTranscriptChunk(text, options = {}) {
    if (!this.isListening) this.start();
    const sessionId = options.sessionId ?? this.sessionId;
    const session = this.store.appendTranscriptChunk({ sessionId, text });
    this.emit("transcript:chunk", { sessionId, text, session });
    if (this.inferrer) {
      void this.inferrer.handleChunk({ sessionId, text, title: options.title, notes: options.notes, brain: options.brain });
    }
    return session;
  }
}
