export class InferenceBuffer {
  constructor({ windowMs = 60_000 } = {}) {
    this.windowMs = windowMs;
    this.chunks = [];
  }

  add(text, at = new Date()) {
    const clean = String(text ?? "").trim();
    if (!clean) return this.text();
    const timestamp = at instanceof Date ? at : new Date(at);
    this.chunks.push({ text: clean, at: timestamp });
    this.prune(timestamp);
    return this.text();
  }

  text(now = new Date()) {
    this.prune(now);
    return this.chunks.map((chunk) => chunk.text).join(" ").replace(/\s+/g, " ").trim();
  }

  wordCount(now = new Date()) {
    const text = this.text(now);
    return text ? text.split(/\s+/).length : 0;
  }

  clear() {
    this.chunks = [];
  }

  prune(now = new Date()) {
    const cutoff = now.getTime() - this.windowMs;
    this.chunks = this.chunks.filter((chunk) => chunk.at.getTime() >= cutoff);
  }
}
