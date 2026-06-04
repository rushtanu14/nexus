import SwiftUI
import LocalWorkflowStudioCore
import AppKit

@main
@MainActor
struct LocalWorkflowStudioNativeApp: App {
    @State private var model = StudioModel()
    @State private var nexVoice = NexVoiceStore()
    @State private var echoStore = EchoStore()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model, nexVoice: nexVoice, echoStore: echoStore)
                .frame(minWidth: 1180, idealWidth: 1560, minHeight: 760, idealHeight: 940)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    EngineProcessManager.shared.startIfNeeded()
                    model.startScheduleMonitor()
                    DispatchQueue.main.async {
                        positionPrimaryWindowBottomRight()
                    }
                }
        }
        .defaultSize(width: 1560, height: 940)
        .windowResizability(.contentMinSize)
        MenuBarExtra(isInserted: Binding(get: {
            echoStore.transcriber.isRecording
        }, set: { _ in })) {
            Button("Pause") {
                echoStore.pauseRecording()
            }
            Button("Stop") {
                echoStore.stopRecording()
            }
            Divider()
            Button("Make Note") {
                echoStore.makeNoteFromTranscript()
            }
            Button("Echo Dashboard") {
                echoStore.requestDashboard()
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        } label: {
            Image(systemName: echoStore.transcriber.isRecording ? "waveform.circle.fill" : "waveform.circle")
        }
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

                Button("Talk to Nex") {
                    nexVoice.startListening(using: model, echoStore: echoStore)
                }
                .keyboardShortcut(.space, modifiers: [.shift])
            }
        }
    }

    private func positionPrimaryWindowBottomRight() {
        guard let window = NSApplication.shared.windows.first,
              let screen = window.screen ?? NSScreen.main else {
            return
        }

        let visible = screen.visibleFrame
        let size = window.frame.size
        let width = min(max(size.width, 1180), visible.width)
        let height = min(max(size.height, 760), visible.height)
        let frame = NSRect(
            x: max(visible.minX, visible.maxX - width - 20),
            y: max(visible.minY, min(visible.minY + 20, visible.maxY - height)),
            width: width,
            height: height
        )
        window.setFrame(frame, display: true, animate: false)
    }
}
