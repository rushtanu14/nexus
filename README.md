<div align="center">

<img width="276" height="118" alt="Screenshot 2026-05-31 at 11 48 22 AM" src="https://github.com/user-attachments/assets/fffb4645-d719-4988-938a-bef235ac5283" />

<img width="734" height="462" alt="Screenshot 2026-05-31 at 1 56 01 PM" src="https://github.com/user-attachments/assets/8e6e0ce5-5c80-46d8-bdea-52ccba8d72c4" />

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
