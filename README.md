# Nexus

Nexus is a native macOS prototype for AI-generated local automations. You describe what you want in natural language, Nexus turns it into an editable node canvas, and the local runner keeps risky actions behind dry runs, warnings, and explicit approval.

The first demo is a screenshot-warning sorter: it finds screenshots, checks for warning indicators, proposes file moves, shows the raw script, and requires trust approval before running locally.

## What It Does

- Generates a workflow canvas from a plain-English prompt.
- Lets users drag nodes freely and manually connect node ports.
- Shows warnings in simple language before file, script, or app-control actions.
- Supports dry run, trust approval, local run logs, undo, and macOS Accessibility fallback prompts.
- Bundles as a native `.app` with a generated Nexus icon.
- Includes an in-app walkthrough for prompt generation, canvas editing, trust approval, and permissions.

## Repository Layout

```text
native-macos/
  Package.swift
  Sources/
    LocalWorkflowStudioCore/      # workflow model, graph editing, trust state
    LocalWorkflowStudioNative/    # SwiftUI app shell, canvas, inspector, icon
  Tests/                          # no-framework Swift test runner
  AppBundle/Info.plist            # packaged app metadata
  scripts/build-app.sh            # builds dist/Nexus.app

docs/
  design/                         # visual direction and generated concept art
  superpowers/                    # product/spec/implementation notes
```

## Run In Xcode

1. Open `native-macos/Package.swift` in Xcode.
2. Select the `LocalWorkflowStudioNative` executable scheme.
3. Build and run.

## Run From Terminal

```bash
./run.sh
```

To build without launching the app:

```bash
./run.sh --no-open
```

## Build The App Bundle

```bash
cd native-macos
./scripts/build-app.sh
open dist/Nexus.app
```

The bundle script generates `AppIcon.icns` from `Sources/LocalWorkflowStudioNative/Resources/AppIcon.png`.

## Test

```bash
cd native-macos
swift run LocalWorkflowStudioNativeModelTests
```

## Safety Model

Nexus is designed around local trust controls:

- Dry run before execution.
- Re-approval when scripts, graph connections, or node positions change.
- Plain-language warnings for file moves, raw scripts, and macOS permissions.
- Accessibility control only when a workflow needs UI control.
- Accessibility requests use the native macOS permission prompt and open System Settings directly to Privacy & Security -> Accessibility.
- Local logs and undo metadata for the last run.

## Current Status

This is an early native MVP. The UI, graph editor, warning flow, app icon, packaging script, and model tests are implemented. The actual runner is still a demo spine and should be expanded with real macOS adapters before production use.
