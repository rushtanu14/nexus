# Native macOS Node Canvas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native SwiftUI macOS app for Nexus where AI generates an n8n-style automation node canvas that the user reviews, dry-runs, approves, and runs locally.

**Architecture:** Create a Swift Package that opens directly in Xcode and compiles a native macOS SwiftUI app. The app keeps local demo state in memory, renders an AI-generated node graph, exposes a right inspector for the selected node, and implements the screenshot-cleaner dry-run/approval/run/undo model without Electron or WebView. The generated app icon is bundled as a SwiftPM resource.

**Tech Stack:** Swift 6, SwiftUI, AppKit resource loading, XCTest, Swift Package Manager.

---

## File Structure

- `native-macos/Package.swift`: Swift package manifest for app and tests.
- `native-macos/Sources/LocalWorkflowStudioNative/LocalWorkflowStudioNativeApp.swift`: native macOS entrypoint.
- `native-macos/Sources/LocalWorkflowStudioNative/AppModel.swift`: workflow graph, AI generation, approval, dry run, run, undo, logs.
- `native-macos/Sources/LocalWorkflowStudioNative/ContentView.swift`: app shell, AI prompt, node canvas, inspector, log drawer.
- `native-macos/Sources/LocalWorkflowStudioNative/Resources/AppIcon.png`: generated icon resource.
- `native-macos/Tests/LocalWorkflowStudioNativeTests/AppModelTests.swift`: tests for graph generation, approval invalidation, run/undo, and accessibility prompt.

## Tasks

- [x] Create Swift package and native app target.
- [x] Implement workflow model and demo runner.
- [x] Build n8n-style SwiftUI canvas where AI-generated nodes are connected by edges.
- [x] Add inspector with selected-node parameters, warnings, affected files, trust approval, dry run, run, and undo.
- [x] Add generated icon to the sidebar and package resources.
- [x] Add XCTest coverage for the model.
- [x] Run Swift tests if local toolchain allows it; otherwise report toolchain blocker.

## Follow-up: n8n-style editable canvas

- [x] Restore native macOS chrome and fix panel padding/clipping.
- [x] Add model support for draggable nodes, manual connections, edge removal, and generated node insertion.
- [x] Expose connector ports, drag gestures, and connection controls in the SwiftUI canvas.
- [x] Show editable graph connections in the inspector.
- [x] Add regression coverage for graph editing invalidating trust approval.
- [x] Rebuild, launch, and visually verify the native app bundle.
