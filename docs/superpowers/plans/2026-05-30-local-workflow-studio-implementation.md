# Local Workflow Studio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a dependency-free local demo app that proves chat-first automation creation, dry-run warnings, trust approval/versioning, real screenshot cleanup, run logs, controlled browser recording/replay, and contextual Accessibility permission prompting.

**Architecture:** A Node HTTP server serves a static app and JSON APIs. The runner stores workflow state locally, executes safe filesystem actions in a demo workspace, gates raw scripts behind explicit hash-based approval, and exposes a browser-recorder demo in the frontend. The first build intentionally avoids package downloads so it can run immediately in the current empty workspace.

**Tech Stack:** Node.js built-in modules, vanilla HTML/CSS/JavaScript, JSON file state, local filesystem adapters.

---

## File Structure

- `package.json`: scripts for dev, smoke tests, and no-dependency project metadata.
- `server.mjs`: local HTTP server, static file serving, CSRF-style local token, API routing.
- `src/workflowEngine.mjs`: workflow planner, dry-run engine, approval hashing, runner, undo, logs, demo workspace helpers.
- `public/index.html`: app shell.
- `public/styles.css`: product UI styling.
- `public/app.js`: client state, chat generation, dry run/review/run controls, recorder/replay UI.
- `tests/workflowEngine.test.mjs`: Node tests for planner/runner/trust/log behavior.
- `.gitignore`: local state and demo artifacts.

## Tasks

### Task 1: Project Skeleton And Local Server

- [x] Create package metadata and scripts.
- [x] Implement local HTTP server with static serving and token-protected JSON APIs.
- [x] Add state directory creation.

### Task 2: Workflow Engine

- [x] Implement deterministic demo planner for screenshot cleaner, browser recorder, and accessibility fallback prompts.
- [x] Implement dry-run warnings and exact file impact.
- [x] Implement approval signatures for raw scripts and permission changes.
- [x] Implement screenshot cleaner run and undo in a demo workspace.
- [x] Implement run logs and state persistence.

### Task 3: Product UI

- [x] Build chat-first dashboard.
- [x] Build review/dry-run/trust panel.
- [x] Build automation dashboard and logs.
- [x] Build controlled browser recorder/replay demo.
- [x] Build contextual Accessibility permission prompt.

### Task 4: Verification

- [x] Add Node tests for engine behavior.
- [x] Run `npm test`.
- [x] Start local dev server.
- [x] Browser-verify first meaningful render and primary interactions.
- [x] Report limitations honestly.

## Scope Notes

- The screenshot cleaner is real and operates on `demo-workspace/Desktop` by default for safety.
- The controlled browser recorder is real inside the app's controlled demo surface; it is not a system-wide browser extension.
- Accessibility permission prompting is contextual in the UI; true macOS Accessibility control needs a packaged/native shell later.
- Cloud AI planning is represented by a deterministic demo planner until API credentials are added.
