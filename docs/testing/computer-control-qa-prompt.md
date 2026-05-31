# Nexus Computer-Control QA Prompt

Use this prompt when asking an agent to test Nexus through direct macOS UI control.

## Mission

Test every visible Nexus control and core workflow through computer control. Verify the app works as a user would experience it, not only through unit tests.

## Safety Rules

- Do not grant macOS Accessibility permission during QA.
- Do not toggle anything in System Settings.
- Do not move, rename, delete, upload, or transmit real user files.
- Do not interact with unrelated apps except to return focus or close windows opened by this test.
- Prefer build-only and in-memory demo flows. The demo runner must not perform real file moves.
- After testing, close Nexus and any System Settings window opened by the permission test.
- If Nexus appears in Accessibility during testing, run `tccutil reset Accessibility com.rushil.nexus` after the test and confirm the app is not enabled.
- Leave build artifacts ignored under `native-macos/.build/` and `native-macos/dist/`.
- If any step would alter the user's computer setup, stop and report the risk instead of continuing.

## Setup

1. Confirm the repo is clean or record existing unrelated changes.
2. Run `./run.sh --no-open` from the repo root.
3. Launch `native-macos/dist/Nexus.app`.
4. Capture the initial app window.

## Full UI Coverage

### Title Bar

- Click the walkthrough `?` button.
- Verify the walkthrough opens.
- Click the titlebar play button.
- Verify the runner status or log updates for a dry run.
- Click the titlebar wand button.
- Verify the workflow regenerates and the runner status updates.

### Walkthrough

- Verify Step 1 content appears.
- Click `Next` through every step.
- Click `Back` at least once.
- Click a step in the map.
- On the permissions step, click `Open Accessibility Settings`.
- Verify the macOS Accessibility prompt and/or System Settings Accessibility pane appears.
- Do not grant permission or toggle any setting.
- Return to Nexus and close the walkthrough.

### Prompt Panel

- Replace the prompt with a safe test prompt:
  `QA ONLY: create a local demo workflow that sorts screenshots, warns before moving files, logs locally, and does not touch real files.`
- Click `Generate canvas`.
- Verify nodes and warnings remain visible.
- Click `Dry run`.
- Verify dry-run logs appear.
- Click `Add warning`.
- Verify a new warning/review node appears and is selected.
- Click `Add app control`.
- Verify a new app-control/accessibility node appears and is selected.

### Canvas

- Click at least three node cards and verify the inspector title changes.
- Drag one node and verify it moves.
- If the available computer-control tool cannot perform drag gestures, record that limitation instead of faking the result.
- Start a connection from one node output dot and finish it on another node input dot.
- Verify the new connection appears.
- Click the small `x` on a connection line.
- Verify the connection disappears.
- Use another connection delete path from the inspector connection row.
- Verify deleting a connection invalidates trust approval.

### Inspector

- Select a warning node.
- Verify plain-English summary, parameters, warnings, affected files, raw script, and connections sections are visible.
- Click `Trust this version`.
- Verify the trust button changes to trusted state.
- Click `Run Locally`.
- Verify the run completes only after trust approval.
- Click `Undo`.
- Verify the undo log appears.
- Click `Request Accessibility`.
- Verify Nexus asks through macOS and opens the Accessibility settings pane.
- Do not grant permission. Close System Settings or leave it unchanged and return to Nexus.

### Logs

- Verify logs include generation, dry run, trust, run, undo, canvas edit, and permission-request entries where applicable.
- Verify no crash dialogs appear.
- Verify no unrelated app or real file state changed.

## Cleanup

1. Close Nexus.
2. Close any System Settings window opened by the test without changing settings.
3. Confirm `git status --ignored -sb` shows only ignored build artifacts unless the QA prompt/report itself is intentionally being added.
4. Report every pass/fail item, screenshots captured, commands run, and any skipped checks.
