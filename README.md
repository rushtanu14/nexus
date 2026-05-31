<div align="center">
  
<img width="1470" height="920" alt="Screenshot 2026-05-31 at 2 09 15 AM" src="https://github.com/user-attachments/assets/6323fbef-413a-45e6-bc9e-d3982a200a2a" />

</div>


# dev notes

## repo

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

## XCODE

1. Open `native-macos/Package.swift` in Xcode.
2. Select the `LocalWorkflowStudioNative` executable scheme.
3. Build and run.

## terminal

```bash
./run.sh
```

no app:

```bash
./run.sh --no-open
```

## app bundle

```bash
cd native-macos
./scripts/build-app.sh
open dist/Nexus.app
```

The bundle script generates `AppIcon.icns` from `Sources/LocalWorkflowStudioNative/Resources/AppIcon.png`.

## test

```bash
cd native-macos
swift run LocalWorkflowStudioNativeModelTests
```

## local workflow engine

The repository also includes a Node.js workflow engine with AI-generated node shapes and deterministic local runner steps.

```bash
npm test
npm start
```

The local API listens on `http://127.0.0.1:3131`. Browser click/fill, MCP calls, and AI inference use injectable adapters; filesystem, shell, HTTP, and basic browser navigation/extraction have local implementations.

Node generation uses the local Ollama model `qwen2.5-coder:7b`. Install and start it with:

```bash
npm run model:pull
npm run model:serve
```

With Ollama and `npm start` running, verify the same frontend/backend path used by the desktop app:

```bash
cd native-macos
swift run LocalWorkflowStudioNativeIntegrationTests
```
