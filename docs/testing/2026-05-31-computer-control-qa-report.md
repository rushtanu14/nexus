# Nexus Computer-Control QA Report

## Scope

Tested the native macOS Nexus app through direct computer control using a safe QA-only workflow prompt. The run avoided real file movement, did not grant Accessibility permission, and reset the Accessibility TCC entry after permission testing.

## Commands

- `./run.sh --no-open` passed and built `native-macos/dist/Nexus.app`.
- `swift run LocalWorkflowStudioNativeModelTests` passed after rerunning outside the sandbox so SwiftPM could use the normal Swift/Clang caches.
- `./run.sh` launched the rebuilt app.
- `tccutil reset Accessibility com.rushil.nexus` ran after Accessibility testing and reported success.

## Fix Made During QA

- Found that the `Canvas / Code / Runs` segmented control changed its selected accessibility value but still showed the canvas for every tab.
- Fixed it by wiring the segmented control to real state and adding functional Code and Runs surfaces.

## Passed

- Prompt entry accepted the safe QA-only automation request.
- `Generate canvas` refreshed the workflow and log state.
- Prompt-panel `Dry run` and titlebar play both changed the runner to dry-run behavior.
- Titlebar wand regenerated the workflow.
- `Add warning` created and selected a new Review Warnings node.
- `Add app control` created and selected a new App Control node.
- Canvas tab rendered movable workflow nodes, connection dots, wire delete controls, and minimap.
- Code tab showed the generated script, trust state, and plain warnings.
- Runs tab showed the local timeline including generation, dry run, node edits, trust, run, undo, and permission request events.
- Node selection changed the inspector for Trigger, Move Files, Review Warnings, and App Control.
- Connection creation worked by starting from an output dot and finishing on another node.
- Inspector connection deletion removed the created connection and logged the removal.
- Canvas wire `x` deletion removed an existing connection and logged the removal.
- Untrusted `Run Locally` was blocked.
- `Trust this version` changed the approval state to trusted.
- Trusted `Run Locally` completed in the app model only.
- `Undo` restored the simulated moved-file metadata in the app model.
- `Request Accessibility` opened the walkthrough permission step and System Settings directly to Accessibility.
- System Settings showed Nexus in Accessibility with the switch off; no permission was granted.
- Walkthrough `?`, map step selection, Back, Next, Done, and close controls worked.

## Safety Cleanup

- Closed System Settings.
- Ran `tccutil reset Accessibility com.rushil.nexus` after the permission test.
- Closed the Nexus window and killed the remaining app process so all in-memory QA workflow state was discarded.
- No real screenshots or user files were moved by the app; the run/undo path is currently simulated in the model.

## Remaining Tool Limitation

- True pointer dragging was not executed because the available Computer Use tool exposes click, type, and set-value operations, but no drag gesture. The model-level drag behavior is still covered by `LocalWorkflowStudioNativeModelTests` through `setNodePosition`.
