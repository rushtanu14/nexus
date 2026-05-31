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
                .frame(minWidth: 1160, idealWidth: 1240, minHeight: 760, idealHeight: 820)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        centerPrimaryWindow()
                    }
                }
        }
        .defaultSize(width: 1240, height: 820)
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
        let width = min(max(1160, visible.width - 120), 1240)
        let height = min(max(760, visible.height - 120), 820)
        let frame = NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
        window.setFrame(frame, display: true, animate: false)
    }
}
