import SwiftUI
import LocalWorkflowStudioCore
import AppKit

@main
struct LocalWorkflowStudioNativeApp: App {
    @State private var model = StudioModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1180, idealWidth: 1560, minHeight: 760, idealHeight: 940)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    EngineProcessManager.shared.startIfNeeded()
                    DispatchQueue.main.async {
                        centerPrimaryWindow()
                    }
                }
        }
        .defaultSize(width: 1560, height: 940)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Generate Workflow") {
                    model.generateWorkflow()
                }
                .keyboardShortcut("g", modifiers: [.command])

                Button("Dry Run") {
                    model.dryRun()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }

    private func centerPrimaryWindow() {
        guard let window = NSApplication.shared.windows.first,
              let screen = window.screen ?? NSScreen.main else {
            return
        }

        let visible = screen.visibleFrame
        let width = min(max(1180, visible.width - 100), 1560)
        let height = min(max(760, visible.height - 100), 940)
        let frame = NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
        window.setFrame(frame, display: true, animate: false)
    }
}
