import SwiftUI
import AppKit
import ApplicationServices
import LocalWorkflowStudioCore

@MainActor
struct ContentView: View {
    @Bindable var model: StudioModel
    @Bindable var nexVoice: NexVoiceStore
    @Bindable var echoStore: EchoStore
    @State private var walkthroughOpen = false
    @State private var walkthroughStepIndex = 0
    @State private var selectedSection: StudioSection = .hub

    var body: some View {
        GeometryReader { proxy in
            shell(compact: proxy.size.width < 1360)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .foregroundStyle(StudioPalette.text)
        .font(StudioType.body)
        .task {
            await model.refreshSavedNodes()
            await model.refreshSavedWorkflows()
            await model.refreshBrain()
        }
        .onChange(of: nexVoice.requestedSection) { _, section in
            guard let section else { return }
            switch section {
            case "echo": selectedSection = .echo
            case "brain": selectedSection = .brain
            case "hub": selectedSection = .hub
            default: selectedSection = .workflows
            }
            nexVoice.requestedSection = nil
        }
        .onChange(of: echoStore.dashboardRequest) { _, _ in
            selectedSection = .echo
        }
    }

    private func shell(compact: Bool) -> some View {
        ZStack {
            StudioPalette.background
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                TitleBar(model: model) {
                    walkthroughStepIndex = 0
                    walkthroughOpen = true
                }
                Divider().overlay(StudioPalette.line)
                HSplitView {
                    Sidebar(model: model, compact: compact, selectedSection: $selectedSection)
                    switch selectedSection {
                    case .hub:
                        NexusHubSurface(model: model) {
                            selectedSection = .workflows
                        }
                    case .brain:
                        NexBrainSurface(model: model)
                    case .echo:
                        NexEchoSurface(model: model, store: echoStore)
                    case .workflows:
                        PromptPanel(model: model, compact: compact)
                        CanvasPanel(model: model, compact: compact)
                        InspectorPanel(model: model, compact: compact) {
                            requestAccessibilityPermission()
                        }
                    }
                }
                Divider().overlay(StudioPalette.line)
                LogDrawer(model: model)
            }

            if walkthroughOpen {
                WalkthroughOverlay(
                    stepIndex: $walkthroughStepIndex,
                    close: {
                        walkthroughOpen = false
                    },
                    requestAccessibility: {
                        requestAccessibilityPermission(showWalkthrough: false)
                    }
                )
                .zIndex(1)
            }

            if nexVoice.isVisible {
                FloatingNexOverlay(model: model, voice: nexVoice)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 18)
                    .padding(.top, 78)
                    .zIndex(2)
            }
        }
    }

    private func requestAccessibilityPermission(showWalkthrough: Bool = true) {
        model.requestAccessibility()
        AccessibilityPermissionHelper.requestSystemPrompt()
        AccessibilityPermissionHelper.openAccessibilitySettings()
        if showWalkthrough {
            walkthroughStepIndex = WalkthroughStep.permissionIndex
            walkthroughOpen = true
        }
    }
}

private enum StudioSection: String {
    case hub = "nexus hub"
    case workflows
    case brain = "nex brain"
    case echo = "nex echo"
}

private struct TitleBar: View {
    @Bindable var model: StudioModel
    var onOpenWalkthrough: () -> Void

    var body: some View {
        ZStack {
            PanelBackdrop(imageName: "TitleBarBackground", scrimOpacity: 0.55, scaleY: 0.65)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Text("NEXUS")
                    .font(StudioType.brandWordmark)
                    .tracking(2)
                    .foregroundStyle(StudioPalette.text)
                Spacer()
                StatusPill(label: "runner", value: model.runnerStatus, color: StudioPalette.accent)
                StatusPill(label: "permissions", value: model.workflow.accessibilityRequested ? "requested" : "local", color: model.workflow.accessibilityRequested ? StudioPalette.amber : StudioPalette.accent)
                Button(action: onOpenWalkthrough) {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(IconButtonStyle())
                .help("Open walkthrough")
                Button(action: model.dryRun) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(IconButtonStyle())
                Button(action: model.generateWorkflow) {
                    Image(systemName: "wand.and.sparkles")
                }
                .buttonStyle(IconButtonStyle())
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 52)
    }
}

private enum AccessibilityPermissionHelper {
    @discardableResult
    static func requestSystemPrompt() -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct WalkthroughStep: Identifiable {
    var id: String
    var icon: String
    var title: String
    var detail: String
    var checks: [String]

    static let permissionIndex = 3

    static let steps = [
        WalkthroughStep(
            id: "prompt",
            icon: "wand.and.sparkles",
            title: "Describe the automation",
            detail: "Start with plain English. Nexus turns the request into a local workflow canvas instead of making you build every node by hand.",
            checks: [
                "Use the prompt box for the goal",
                "Generate canvas to refresh the graph",
                "The generated script stays visible before running"
            ]
        ),
        WalkthroughStep(
            id: "canvas",
            icon: "point.3.connected.trianglepath.dotted",
            title: "Edit the node canvas",
            detail: "The canvas works like an n8n-style editor: drag nodes around, connect output dots to input dots, and click the small x on a wire to delete a connection.",
            checks: [
                "Drag a node to reorganize the flow",
                "Use right-side dots to start connections",
                "Use wire x buttons or the inspector to remove connections"
            ]
        ),
        WalkthroughStep(
            id: "review",
            icon: "checkmark.shield",
            title: "Dry run, then trust",
            detail: "Nexus blocks execution until the exact workflow version is trusted. If you move nodes, change wires, or change scripts, approval is required again.",
            checks: [
                "Dry Run shows impact first",
                "Warnings explain risks simply",
                "Run Locally only works after trust approval"
            ]
        ),
        WalkthroughStep(
            id: "permissions",
            icon: "accessibility",
            title: "Enable computer control only when needed",
            detail: "For workflows that must click or type in other apps, Nexus asks macOS for Accessibility permission and opens the exact System Settings screen where you can add the app.",
            checks: [
                "macOS shows its own permission prompt",
                "System Settings opens to Accessibility",
                "You can quit anytime before granting access"
            ]
        ),
        WalkthroughStep(
            id: "logs",
            icon: "clock.arrow.circlepath",
            title: "Check logs and undo",
            detail: "Local run logs show what happened, and the demo keeps undo metadata for the last file-moving run.",
            checks: [
                "Logs stay local",
                "Undo is available for the last run",
                "Accessibility is not requested unless needed"
            ]
        )
    ]
}

private struct WalkthroughOverlay: View {
    @Binding var stepIndex: Int
    var close: () -> Void
    var requestAccessibility: () -> Void

    private var steps: [WalkthroughStep] {
        WalkthroughStep.steps
    }

    private var activeStep: WalkthroughStep {
        steps[min(max(stepIndex, 0), steps.count - 1)]
    }

    private var isLastStep: Bool {
        stepIndex >= steps.count - 1
    }

    private var progress: CGFloat {
        CGFloat(stepIndex + 1) / CGFloat(steps.count)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("Nexus walkthrough", systemImage: "sparkles")
                            .font(.system(size: 13).weight(.bold))
                            .foregroundStyle(StudioPalette.accentBright)
                        Spacer()
                        Button(action: close) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(IconButtonStyle())
                        .help("Close walkthrough")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Step \(stepIndex + 1) of \(steps.count)")
                            .font(.system(size: 11).weight(.bold))
                            .foregroundStyle(StudioPalette.muted)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(StudioPalette.panelStrong)
                                Capsule()
                                    .fill(StudioPalette.accentBright)
                                    .frame(width: proxy.size.width * progress)
                            }
                        }
                        .frame(height: 7)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(StudioPalette.accentSoft)
                            Image(systemName: activeStep.icon)
                                .font(.system(size: 24).weight(.semibold))
                                .foregroundStyle(StudioPalette.accentBright)
                        }
                        .frame(width: 54, height: 54)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(activeStep.title)
                                .font(.system(size: 23).weight(.bold))
                            Text(activeStep.detail)
                                .font(.system(size: 14))
                                .foregroundStyle(StudioPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(activeStep.checks, id: \.self) { check in
                            Label(check, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 13).weight(.medium))
                                .foregroundStyle(StudioPalette.text)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudioPalette.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))

                    if activeStep.id == "permissions" {
                        Button(action: requestAccessibility) {
                            Label("Open Accessibility Settings", systemImage: "gearshape")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }

                    HStack(spacing: 10) {
                        Button("Back") {
                            stepIndex = max(0, stepIndex - 1)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(stepIndex == 0)

                        Button(isLastStep ? "Done" : "Next") {
                            if isLastStep {
                                close()
                            } else {
                                stepIndex = min(steps.count - 1, stepIndex + 1)
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(22)
                .frame(width: 520)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Map")
                        .font(.system(size: 11).weight(.bold))
                        .foregroundStyle(StudioPalette.muted)
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        WalkthroughMapRow(
                            step: step,
                            index: index,
                            active: index == stepIndex,
                            select: {
                                stepIndex = index
                            }
                        )
                    }
                    Spacer()
                }
                .padding(18)
                .frame(width: 230)
                .background(StudioPalette.sidebar)
            }
            .frame(width: 750, height: 520)
            .background(StudioPalette.inspector)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(StudioPalette.line))
            .shadow(color: .black.opacity(0.55), radius: 40, x: 0, y: 24)
        }
    }
}

private struct WalkthroughMapRow: View {
    var step: WalkthroughStep
    var index: Int
    var active: Bool
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.system(size: 11).weight(.bold))
                    .frame(width: 24, height: 24)
                    .background(active ? StudioPalette.accentBright : StudioPalette.panelStrong)
                    .foregroundStyle(active ? Color.black.opacity(0.85) : StudioPalette.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(step.title)
                        .font(.system(size: 12).weight(.semibold))
                        .lineLimit(1)
                    Text(step.id.capitalized)
                        .font(.system(size: 10).weight(.medium))
                        .foregroundStyle(StudioPalette.muted)
                }

                Spacer()
            }
            .padding(10)
            .background(active ? StudioPalette.accentSoft : StudioPalette.panel)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(active ? StudioPalette.accent.opacity(0.8) : StudioPalette.line))
        }
        .buttonStyle(.plain)
    }
}

private struct Sidebar: View {
    @Bindable var model: StudioModel
    var compact: Bool
    @Binding var selectedSection: StudioSection

    var body: some View {
        ZStack(alignment: .topLeading) {
            PanelBackdrop(imageName: "LeftPanelBackground", scrimOpacity: 0.08)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: compact ? 14 : 18) {
                VStack(spacing: 10) {
                    AppIconImage()
                        .frame(width: compact ? 44 : 78, height: compact ? 44 : 78)
                        .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 12, style: .continuous))
                        .shadow(color: StudioPalette.accentBright.opacity(0.15), radius: 18, x: 0, y: 12)
                    if !compact {
                        Text("NEXUS")
                            .font(.system(size: 13).weight(.heavy))
                            .tracking(2)
                        Text("v0.1.0 native")
                            .font(.system(size: 11).weight(.medium))
                            .foregroundStyle(StudioPalette.muted)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, compact ? 2 : 10)

                SidebarButton(icon: "square.grid.2x2", label: "nexus hub", active: selectedSection == .hub, compact: compact) {
                    selectedSection = .hub
                }
                SidebarButton(icon: "point.3.connected.trianglepath.dotted", label: "nexspace", active: selectedSection == .workflows, compact: compact) {
                    selectedSection = .workflows
                }
                SidebarButton(icon: "brain.head.profile", label: "nex brain", active: selectedSection == .brain, compact: compact) {
                    selectedSection = .brain
                }
                SidebarButton(icon: "waveform", label: "nex echo", active: selectedSection == .echo, compact: compact) {
                    selectedSection = .echo
                }

                Spacer()

                if compact {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(StudioPalette.accent)
                        .frame(maxWidth: .infinity)
                        .help("runner local")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("runner local", systemImage: "circle.fill")
                            .foregroundStyle(StudioPalette.accent)
                        Text("workspace")
                            .foregroundStyle(StudioPalette.muted)
                        Text("~/Workflow Studio")
                            .foregroundStyle(StudioPalette.accent)
                            .font(.system(size: 11, design: .monospaced).monospaced())
                    }
                    .font(.system(size: 12).weight(.medium))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudioPalette.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
                }
            }
            .padding(compact ? 10 : 16)
        }
        .frame(minWidth: compact ? 72 : 138, idealWidth: compact ? 88 : 184, maxWidth: 280)
        .layoutPriority(4)
        .clipped()
    }
}

private struct NexusHubSurface: View {
    @Bindable var model: StudioModel
    var openBuilder: () -> Void

    var body: some View {
        ReactiveBackgroundContainer(color: StudioPalette.canvas) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Nexus Hub")
                                .font(StudioType.pageTitle)
                            Text("Your automated work at a glance. Each card leads with the deliverable it must prove.")
                                .font(StudioType.body)
                                .foregroundStyle(StudioPalette.muted)
                        }
                        Spacer()
                        if model.hasWorkflow {
                            Button("save current workflow", action: model.saveCurrentWorkflow)
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        Button("build workflow", action: openBuilder)
                            .buttonStyle(PrimaryButtonStyle())
                    }

                    if model.savedWorkflows.isEmpty {
                        EmptySurface(icon: "square.grid.2x2", title: "No saved workflows yet", detail: "Build a workflow, name its deliverables, then save it to the Hub.")
                            .frame(maxWidth: .infinity, minHeight: 420)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 14)], spacing: 14) {
                            ForEach(model.savedWorkflows) { saved in
                                HubWorkflowCard(saved: saved, delete: {
                                    model.deleteWorkflow(saved)
                                }) {
                                    model.loadWorkflow(saved)
                                    openBuilder()
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 760)
    }
}

private struct HubWorkflowCard: View {
    var saved: SavedWorkflow
    var delete: () -> Void
    var open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text(saved.workflow.name)
                        .font(StudioType.cardTitle)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: saved.workflow.executionOutput == nil ? "clock" : "checkmark.circle.fill")
                        .foregroundStyle(saved.workflow.executionOutput == nil ? StudioPalette.amber : StudioPalette.accentBright)
                    Button(action: delete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(IconButtonStyle())
                }
                ForEach(saved.workflow.nodes.prefix(4)) { node in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.deliverable)
                            .font(.system(size: 13).weight(.semibold))
                            .lineLimit(2)
                        Text(node.schedule)
                            .font(.system(size: 11))
                            .foregroundStyle(StudioPalette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(StudioPalette.panelStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(saved.workflow.groupedSchedule.isEmpty ? "Independent node timing" : "Grouped: \(saved.workflow.groupedSchedule)")
                    .font(.system(size: 11).weight(.medium))
                    .foregroundStyle(StudioPalette.accentBright)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}

@MainActor
private struct NexEchoSurface: View {
    @Bindable var model: StudioModel
    @Bindable var store: EchoStore
    @State private var isEditingNotes = false

    var body: some View {
        ReactiveBackgroundContainer(color: StudioPalette.canvas) {
            HSplitView {
                VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("ECHOS")
                            .font(StudioType.echoMetadata)
                            .tracking(1.2)
                            .foregroundStyle(StudioPalette.muted)
                        Spacer()
                        Button(action: store.createEcho) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(IconButtonStyle())
                    }
                    if store.sessions.isEmpty {
                        Text("Start a recording to create your first echo.")
                            .font(StudioType.echoSecondary)
                            .foregroundStyle(StudioPalette.muted)
                    } else {
                        ForEach(store.sessions) { session in
                            HStack(spacing: 6) {
                                Button {
                                    store.select(session)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.name).font(StudioType.echoBody.weight(.medium))
                                        Text(session.createdAt, style: .date)
                                            .font(StudioType.echoMetadata)
                                            .foregroundStyle(StudioPalette.muted)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    store.select(session)
                                    store.deleteSelected()
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(IconButtonStyle())
                                .help("Delete echo")
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(store.selectedID == session.id ? StudioPalette.accentSoft : StudioPalette.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Spacer()
                }
                .padding(16)
                .frame(minWidth: 190, idealWidth: 230, maxWidth: 280)
                .background(StudioPalette.sidebar)

                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nex Echo")
                                .font(StudioType.echoTitle)
                            Text("Low-latency voice transcription and polished meeting notes.")
                                .font(StudioType.echoSecondary)
                                .foregroundStyle(StudioPalette.muted)
                        }
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(Self.duration(store.elapsed))
                                .font(StudioType.code)
                                .foregroundStyle(StudioPalette.accentBright)
                        }
                        Button(action: store.toggleRecording) {
                            Label(store.transcriber.isRecording ? "stop recording" : "start recording", systemImage: store.transcriber.isRecording ? "stop.fill" : "mic.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }

                    if store.selectedSession == nil {
                        EmptySurface(icon: "waveform", title: "Start a new echo", detail: "One click begins a named transcription session.")
                    } else {
                        HStack {
                            TextField("Echo name", text: $store.sessionName)
                                .font(StudioType.echoCardTitle)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { store.renameSelected(store.sessionName) }
                            Button("save name") { store.renameSelected(store.sessionName) }
                                .buttonStyle(SecondaryButtonStyle())
                            Button(role: .destructive) {
                                store.deleteSelected()
                            } label: {
                                Label("delete", systemImage: "trash")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                        HSplitView {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("LIVE TRANSCRIPT").font(StudioType.echoMetadata).tracking(1.2).foregroundStyle(StudioPalette.muted)
                                ScrollView {
                                    MarkdownText(store.transcriber.isRecording ? store.transcriber.transcript : (store.selectedSession?.transcript ?? ""))
                                        .font(StudioType.echoBody)
                                }
                            }
                            .padding(14)
                            .background(StudioPalette.panel)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                Text("NOTES").font(StudioType.echoMetadata).tracking(1.2).foregroundStyle(StudioPalette.muted)
                                    Spacer()
                                    Button(isEditingNotes ? "done editing" : "edit raw") { isEditingNotes.toggle() }
                                        .buttonStyle(SecondaryButtonStyle())
                                    Button("polish with nex") { store.polishNotes(using: model) }
                                        .buttonStyle(SecondaryButtonStyle())
                                }
                                if isEditingNotes {
                                    TextEditor(text: Binding(get: { store.selectedSession?.notes ?? "" }, set: { store.updateNotes($0) }))
                                        .font(StudioType.echoBody)
                                        .scrollContentBackground(.hidden)
                                        .background(StudioPalette.panelStrong)
                                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                } else {
                                    ScrollView {
                                        MarkdownText(store.selectedSession?.notes ?? "")
                                            .font(StudioType.echoBody)
                                            .padding(10)
                                    }
                                    .background(StudioPalette.panelStrong)
                                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                }
                            }
                            .padding(14)
                            .background(StudioPalette.panel)
                        }
                        Text(store.status)
                            .font(StudioType.echoSecondary)
                            .foregroundStyle(StudioPalette.muted)
                    }
                }
                .padding(24)
            }
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

private struct NexBrainSurface: View {
    @Bindable var model: StudioModel

    private var catalog: [String] {
        model.brainConfig.provider == "ollama" ? model.brainCatalog.ollama : model.brainCatalog.lmstudio
    }

    var body: some View {
        ReactiveBackgroundContainer(color: StudioPalette.canvas) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Nex Brain")
                            .font(StudioType.pageTitle)
                        Text("Choose the model Nex uses to turn requests into automation nodes.")
                            .font(StudioType.body)
                            .foregroundStyle(StudioPalette.muted)
                    }

                    VStack(alignment: .leading, spacing: 15) {
                        BrainField(title: "Provider") {
                            Picker("Provider", selection: Binding(
                                get: { model.brainConfig.provider },
                                set: { model.selectBrainProvider($0) }
                            )) {
                                Text("Ollama").tag("ollama")
                                Text("LM Studio").tag("lmstudio")
                                Text("OpenAI-compatible API").tag("openai-compatible")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 360, alignment: .leading)
                        }

                        if model.brainConfig.provider != "openai-compatible" {
                            BrainField(title: "Quick model picker") {
                                Picker("Model", selection: Binding(
                                    get: { model.brainConfig.model },
                                    set: { model.selectBrainModel($0) }
                                )) {
                                    ForEach(catalog, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: 360, alignment: .leading)
                            }
                        }

                        BrainField(title: "Model name") {
                            TextField("model identifier", text: $model.brainConfig.model)
                                .textFieldStyle(.roundedBorder)
                        }

                        if model.brainConfig.provider == "openai-compatible" {
                            BrainField(title: "API key") {
                                SecureField("paste API key", text: $model.brainConfig.apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            BrainField(title: "Compatible endpoint") {
                                TextField("https://api.openai.com/v1", text: $model.brainConfig.baseUrl)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        Text(providerDetail)
                            .font(.system(size: 12))
                            .foregroundStyle(StudioPalette.muted)

                        HStack {
                            Button("save brain", action: model.saveBrain)
                                .buttonStyle(PrimaryButtonStyle())
                            if model.brainConfig.provider != "openai-compatible" {
                                Button("prepare now", action: model.prepareSelectedBrain)
                                    .buttonStyle(SecondaryButtonStyle())
                            }
                            Text(model.brainStatus)
                                .font(.system(size: 12).weight(.medium))
                                .foregroundStyle(StudioPalette.accentBright)
                            Spacer()
                            Button {
                                Task { await model.refreshBrain() }
                            } label: {
                                Label("refresh", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(18)
                    .background(StudioPalette.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
                }
                .padding(24)
            }
        }
        .frame(minWidth: 760)
    }

    private var providerDetail: String {
        switch model.brainConfig.provider {
        case "ollama": return "Nexus can start Ollama if it is installed. Use prepare now to pull the selected model before chatting."
        case "lmstudio": return "Use prepare now to start the LM Studio server, download the selected model if needed, and load it."
        default: return "Paste a model name and key. The endpoint defaults to OpenAI and can be changed for any OpenAI-compatible provider."
        }
    }
}

private struct BrainField<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 11).weight(.bold))
                .foregroundStyle(StudioPalette.muted)
            content
        }
    }
}

private struct SidebarButton: View {
    var icon: String
    var label: String
    var active: Bool
    var compact: Bool
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 0 : 10) {
                Image(systemName: icon)
                    .frame(width: compact ? 34 : 18)
                if !compact {
                    Text(label)
                    Spacer()
                }
            }
            .font(.system(size: 14).weight(.medium))
            .padding(.horizontal, compact ? 0 : 12)
            .frame(height: 42)
            .frame(maxWidth: .infinity)
            .background(active ? StudioPalette.accentSoft : Color.clear)
            .foregroundStyle(active ? StudioPalette.accentBright : StudioPalette.text)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(active ? StudioPalette.accent.opacity(0.85) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

private struct PromptPanel: View {
    @Bindable var model: StudioModel
    var compact: Bool

    var body: some View {
        ReactiveBackgroundContainer(color: StudioPalette.background) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                            Text("ask AI to build a workflow")
                                .font(StudioType.cardTitle)
                    Text("generated locally with Ollama")
                        .font(StudioType.secondary)
                        .foregroundStyle(StudioPalette.muted)
                }

                if model.hasWorkflow {
                    VStack(alignment: .leading, spacing: 10) {
                        Bubble(text: model.workflow.prompt, sender: "You", alignRight: true)
                        Bubble(text: "Generated executable runner steps with the local model.", sender: "Local AI", alignRight: false)
                    }
                }

                HStack {
                    Label("Use floating Nex or press Command-Shift-Space to build automations.", systemImage: "mic.fill")
                        .font(StudioType.secondary)
                        .foregroundStyle(StudioPalette.muted)
                    Button(action: model.dryRun) {
                        Label("dry run", systemImage: "play")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!model.hasWorkflow)
                }

                    if model.hasWorkflow {
                        Text("current automation")
                        .font(StudioType.metadata)
                        .foregroundStyle(StudioPalette.muted)
                        .padding(.top, 4)

                    AutomationRow(title: model.workflow.name, subtitle: "Generated from pasted details", active: true)
                }

                if let output = model.workflow.executionOutput {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("task completed", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12).weight(.bold))
                            .foregroundStyle(StudioPalette.accentBright)
                        MarkdownText(output)
                            .font(.system(size: 11))
                            .lineLimit(6)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudioPalette.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.accent.opacity(0.8)))
                }

                Spacer()

            }
            .padding(.horizontal, compact ? 14 : 20)
            .padding(.vertical, 18)
        }
        .frame(minWidth: 244, idealWidth: compact ? 286 : 324, maxWidth: 520)
        .layoutPriority(3)
    }
}

private enum CanvasTab: String, CaseIterable, Identifiable {
    case canvas = "canvas"
    case code = "code"
    case runs = "runs"
    case nodes = "your nodes"

    var id: String { rawValue }

    var guidance: String {
        switch self {
        case .canvas: return "Drag nodes. Connect output dots to input dots."
        case .code: return "Inspect the generated local script before approving."
        case .runs: return "Review local dry runs, approvals, runs, and undo history."
        case .nodes: return "Reload executable nodes saved by the local backend."
        }
    }

    func metricValue(compact: Bool, logCount: Int) -> String {
        switch self {
        case .canvas: return compact ? "66%" : "100%"
        case .code: return "Script"
        case .runs: return "\(logCount)"
        case .nodes: return "Saved"
        }
    }
}

private struct CanvasPanel: View {
    @Bindable var model: StudioModel
    var compact: Bool
    @State private var dragOrigins: [UUID: CGPoint] = [:]
    @State private var selectedTab: CanvasTab = .canvas

    var body: some View {
        let scale: CGFloat = compact ? 0.66 : 1

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(CanvasTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Text(tab.rawValue)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CanvasTabButtonStyle(isSelected: selectedTab == tab))
                    }
                }
                .padding(3)
                .background(StudioPalette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
                .frame(width: compact ? 320 : 368)
                Spacer()
                Text(model.pendingConnectionSourceID == nil ? selectedTab.guidance : "Choose an input dot to finish the connection.")
                    .font(.system(size: 12).weight(.medium))
                    .foregroundStyle(model.pendingConnectionSourceID == nil ? StudioPalette.muted : StudioPalette.accentBright)
                    .lineLimit(1)
                StatusPill(
                    label: selectedTab == .canvas ? "zoom" : selectedTab.rawValue,
                    value: selectedTab.metricValue(compact: compact, logCount: model.logs.count),
                    color: selectedTab == .runs ? StudioPalette.accent : StudioPalette.muted
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            GeometryReader { proxy in
                switch selectedTab {
                case .canvas:
                    Group {
                            if model.workflow.nodes.isEmpty {
                                ZStack {
                                    WarpingGridBackground(nodes: [])
                                    EmptySurface(
                                        icon: "point.3.connected.trianglepath.dotted",
                                        title: "NexSpace",
                                        detail: "generate, load, and chain nodes together"
                                    )
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ScrollView([.horizontal, .vertical]) {
                                    ZStack(alignment: .topLeading) {
                                        WarpingGridBackground(nodes: model.workflow.nodes)

                                        ForEach(model.workflow.edges) { edge in
                                            if let from = model.workflow.nodes.first(where: { $0.id == edge.from }),
                                               let to = model.workflow.nodes.first(where: { $0.id == edge.to }) {
                                                let fromPoint = nodeCenter(from, scale: scale)
                                                let toPoint = nodeCenter(to, scale: scale)

                                                EdgeLine(from: fromPoint, to: toPoint, isFallback: edge.isFallback)

                                                EdgeDeleteButton(isFallback: edge.isFallback) {
                                                    model.removeEdge(edge.id)
                                                }
                                                .position(edgeDeletePoint(from: fromPoint, to: toPoint))
                                                .help("Delete connection")
                                            }
                                        }

                                        ForEach(model.workflow.nodes) { node in
                                            NodeCard(
                                                node: node,
                                                isSelected: model.selectedNodeID == node.id,
                                                isConnectionSource: model.pendingConnectionSourceID == node.id,
                                                onSelect: {
                                                    model.select(node)
                                                },
                                                onStartConnection: {
                                                    model.beginConnection(from: node.id)
                                                },
                                                onFinishConnection: {
                                                    model.completeConnection(to: node.id)
                                                }
                                            )
                                            .scaleEffect(scale)
                                            .position(nodeCenter(node, scale: scale))
                                            .simultaneousGesture(nodeDragGesture(for: node, scale: scale))
                                        }

                                        if let sourceID = model.pendingConnectionSourceID,
                                           let source = model.workflow.nodes.first(where: { $0.id == sourceID }) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 3).fill(StudioPalette.accent.opacity(0.16))
                                                RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.accentBright, lineWidth: 2)
                                                Image(systemName: "arrow.right")
                                                    .font(.system(size: 13).weight(.bold))
                                                    .foregroundStyle(StudioPalette.accentBright)
                                            }
                                            .frame(width: 42 * scale, height: 42 * scale)
                                            .position(x: nodeCenter(source, scale: scale).x + 94 * scale, y: nodeCenter(source, scale: scale).y)
                                        }

                                        MiniMap(nodes: model.workflow.nodes, edges: model.workflow.edges)
                                            .position(x: 108, y: 92)
                                    }
                                    .frame(width: canvasWidth(viewport: proxy.size.width), height: canvasHeight(viewport: proxy.size.height), alignment: .topLeading)
                                }
                            }
                    }
                    .clipShape(Rectangle())
                case .code:
                    CodeSurface(model: model)
                case .runs:
                    RunsSurface(model: model)
                case .nodes:
                    NodesSurface(model: model)
                }
            }
        }
        .frame(minWidth: compact ? 500 : 650)
        .layoutPriority(10)
        .background(StudioPalette.canvas)
    }

    private func nodeCenter(_ node: WorkflowNode, scale: CGFloat) -> CGPoint {
        CGPoint(x: (node.x + 68) * scale, y: (node.y + 52) * scale)
    }

    private func canvasWidth(viewport: CGFloat) -> CGFloat {
        max(viewport, CGFloat(model.workflow.nodes.map(\.x).max() ?? 0) + 760)
    }

    private func canvasHeight(viewport: CGFloat) -> CGFloat {
        max(viewport, CGFloat(model.workflow.nodes.map(\.y).max() ?? 0) + 560)
    }

    private func edgeDeletePoint(from: CGPoint, to: CGPoint) -> CGPoint {
        CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
    }

    private func nodeDragGesture(for node: WorkflowNode, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let origin = dragOrigins[node.id] ?? CGPoint(x: node.x, y: node.y)
                dragOrigins[node.id] = origin
                model.setNodePosition(
                    id: node.id,
                    x: Double(origin.x + value.translation.width / scale),
                    y: Double(origin.y + value.translation.height / scale)
                )
            }
            .onEnded { _ in
                dragOrigins[node.id] = nil
            }
    }
}

private struct CodeSurface: View {
    @Bindable var model: StudioModel

    var body: some View {
        ReactiveBackgroundContainer(color: StudioPalette.canvas) {
            Group {
                if model.hasWorkflow {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(alignment: .center, spacing: 12) {
                                Label("generated local script", systemImage: "chevron.left.forwardslash.chevron.right")
                                    .font(StudioType.cardTitle)
                                Spacer()
                                StatusPill(
                                    label: "trust",
                                    value: model.approvalRequired ? "review" : "trusted",
                                    color: model.approvalRequired ? StudioPalette.amber : StudioPalette.accent
                                )
                            }

                            Text(model.workflow.rawScript)
                                .font(.system(size: 13, design: .monospaced).monospaced())
                                .foregroundStyle(StudioPalette.code)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(StudioPalette.codeBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
                                .textSelection(.enabled)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Warnings".uppercased())
                                    .font(.system(size: 11).weight(.bold))
                                    .foregroundStyle(StudioPalette.muted)

                                ForEach(model.workflow.warnings, id: \.self) { warning in
                                    Label(warning, systemImage: "exclamationmark.triangle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(StudioPalette.amber)
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(StudioPalette.panel)
                                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
                                }
                            }

                            Text("Raw scripts are visible for inspection. Nexus still uses dry-run and trust approval gates before a local run.")
                                .font(.system(size: 12).weight(.medium))
                                .foregroundStyle(StudioPalette.muted)
                        }
                        .padding(24)
                    }
                } else {
                    EmptySurface(icon: "doc.text", title: "No code yet", detail: "Generated script output will appear here.")
                }
            }
        }
    }
}

private struct RunsSurface: View {
    @Bindable var model: StudioModel

    var body: some View {
        ReactiveBackgroundContainer(color: StudioPalette.canvas) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        Label("local run timeline", systemImage: "clock.arrow.circlepath")
                            .font(StudioType.cardTitle)
                        Spacer()
                        StatusPill(label: "runner", value: model.runnerStatus, color: StudioPalette.accent)
                    }

                    if model.logs.isEmpty {
                        EmptySurface(icon: "clock", title: "No runs yet", detail: "Run history will appear here.")
                            .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        ForEach(model.logs) { log in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(log.node)
                                        .font(.system(size: 12).weight(.bold))
                                        .foregroundStyle(statusColor(log.status))
                                    Text(log.time, style: .time)
                                        .font(.system(size: 11, design: .monospaced).monospaced())
                                        .foregroundStyle(StudioPalette.muted)
                                }
                                .frame(width: 96, alignment: .leading)

                                Text(log.message)
                                    .font(.system(size: 13))
                                    .foregroundStyle(StudioPalette.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(StudioPalette.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
                        }
                    }
                }
                .padding(24)
            }
        }
    }
}

private struct NodesSurface: View {
    @Bindable var model: StudioModel

    var body: some View {
        ReactiveBackgroundContainer(color: StudioPalette.canvas) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        Label("your nodes", systemImage: "square.stack.3d.up")
                            .font(StudioType.cardTitle)
                        Spacer()
                        Button {
                            Task { await model.refreshSavedNodes() }
                        } label: {
                            Label("refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Button("unsave all", action: model.unsaveAllNodes)
                            .buttonStyle(SecondaryButtonStyle())
                    }

                    Text("Generated executable nodes saved by the local backend. Load one to inspect, trust, and run it again.")
                        .font(.system(size: 12).weight(.medium))
                        .foregroundStyle(StudioPalette.muted)

                    if model.savedNodes.isEmpty {
                        EmptySurface(icon: "square.stack.3d.up", title: "No saved nodes yet", detail: "Generate a workflow and it will appear here.")
                            .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        ForEach(model.savedNodes, id: \.id) { node in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: "gearshape.2")
                                    .font(.system(size: 18).weight(.semibold))
                                    .foregroundStyle(StudioPalette.accentBright)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(node.meta.label)
                                        .font(.system(size: 14).weight(.bold))
                                    Text("\(node.meta.app) / \(node.meta.category) / \(node.runner.steps.count) step(s)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(StudioPalette.muted)
                                    Text(node.runner.steps.map(\.primitive).joined(separator: "  ->  "))
                                        .font(.system(size: 11, design: .monospaced).monospaced())
                                        .foregroundStyle(StudioPalette.code)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Button("Load") {
                                    model.loadSavedNode(node)
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                Button {
                                    model.unsaveNode(node)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(IconButtonStyle())
                            }
                            .padding(14)
                            .background(StudioPalette.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
                        }
                    }
                }
                .padding(24)
            }
        }
    }
}

private struct EmptySurface: View {
    var icon: String
    var title: String
    var detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28).weight(.semibold))
                .foregroundStyle(StudioPalette.accentBright)
            Text(title)
                .font(.system(size: 17).weight(.semibold))
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13).weight(.medium))
                    .foregroundStyle(StudioPalette.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InspectorPanel: View {
    @Bindable var model: StudioModel
    var compact: Bool
    var requestAccessibility: () -> Void

    var body: some View {
        ReactiveBackgroundContainer(color: StudioPalette.inspector) {
            VStack(alignment: .leading, spacing: 0) {
                if let node = model.selectedNode {
                    HStack {
                        Label(node.title, systemImage: iconName(for: node.kind))
                            .font(StudioType.cardTitle)
                        Spacer()
                        Text(node.status.rawValue)
                            .font(.system(size: 11).weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(statusColor(node.status).opacity(0.18))
                            .foregroundStyle(statusColor(node.status))
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)

                    Divider().overlay(StudioPalette.line)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            InspectorSection(title: "Plain-English Summary") {
                                Text(summary(for: node))
                                    .foregroundStyle(StudioPalette.muted)
                                    .font(.system(size: 13))
                            }

                            InspectorSection(title: "Hub Deliverable") {
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("Node name", text: Binding(
                                        get: { model.selectedNode?.title ?? "" },
                                        set: { model.updateSelectedNode(title: $0) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    TextField("What must this node prove?", text: Binding(
                                        get: { model.selectedNode?.deliverable ?? "" },
                                        set: { model.updateSelectedNode(deliverable: $0) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                }
                            }

                            InspectorSection(title: "Schedule") {
                                VStack(alignment: .leading, spacing: 8) {
                                    NodeSchedulePill(
                                        schedule: model.selectedNode?.schedule ?? "Manual",
                                        setDaily: model.setSelectedNodeDaily,
                                        setOnce: model.setSelectedNodeRunOnce,
                                        clear: model.clearSelectedNodeSchedule
                                    )
                                    Text(model.workflow.groupedSchedule.isEmpty ? "This node runs on its own timer." : "Workflow timing is on. This node timer is saved but temporarily disregarded.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(StudioPalette.muted)
                                }
                            }

                            InspectorSection(title: "Parameters") {
                                VStack(spacing: 8) {
                                    ForEach(node.parameters.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                        ParameterRow(key: key, value: value)
                                    }
                                }
                            }

                            InspectorSection(title: "Connections") {
                                VStack(spacing: 8) {
                                    let visibleEdges = model.workflow.edges.filter { $0.from == node.id || $0.to == node.id }
                                    if visibleEdges.isEmpty {
                                        Text("No manual connections yet.")
                                            .foregroundStyle(StudioPalette.muted)
                                            .font(.system(size: 12))
                                    } else {
                                        ForEach(visibleEdges) { edge in
                                            ConnectionRow(
                                                edge: edge,
                                                fromTitle: title(for: edge.from),
                                                toTitle: title(for: edge.to),
                                                remove: {
                                                    model.removeEdge(edge.id)
                                                }
                                            )
                                        }
                                    }
                                }
                            }

                            InspectorSection(title: "Warnings") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(model.workflow.warnings, id: \.self) { warning in
                                        Label(warning, systemImage: "exclamationmark.triangle")
                                            .foregroundStyle(StudioPalette.amber)
                                            .font(.system(size: 12))
                                    }
                                }
                            }

                            InspectorSection(title: "Affected Files") {
                                VStack(spacing: 8) {
                                    ForEach(model.workflow.impacts) { item in
                                        ImpactRow(item: item)
                                    }
                                }
                            }

                            InspectorSection(title: "Raw Script") {
                                Text(model.workflow.rawScript)
                                    .font(.system(size: 11, design: .monospaced).monospaced())
                                    .foregroundStyle(StudioPalette.code)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(StudioPalette.codeBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            }

                            if let output = model.workflow.executionOutput {
                                InspectorSection(title: "Last Output") {
                                    MarkdownText(output)
                                        .font(.system(size: 11))
                                        .foregroundStyle(StudioPalette.accentBright)
                                        .padding(12)
                                        .background(StudioPalette.codeBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                    }

                    Divider().overlay(StudioPalette.line)

                    VStack(spacing: 10) {
                        HStack {
                            Button("delete selected node", action: model.deleteSelectedCanvasNode)
                                .buttonStyle(SecondaryButtonStyle())
                            Button("clear canvas", action: model.clearCanvas)
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        Button("save workflow to hub", action: model.saveCurrentWorkflow)
                            .buttonStyle(SecondaryButtonStyle())
                        Button(action: model.approveVersion) {
                            Label(model.approvalRequired ? "trust this version" : "trusted version", systemImage: model.approvalRequired ? "touchid" : "checkmark.shield")
                        }
                        .buttonStyle(TrustButtonStyle(disabledLook: !model.approvalRequired))

                        if compact {
                            Button("dry run", action: model.dryRun).buttonStyle(SecondaryButtonStyle())
                            Button("run locally", action: model.runLocally).buttonStyle(PrimaryButtonStyle())
                            Button("undo", action: model.undoLastRun).buttonStyle(SecondaryButtonStyle())
                            Button("request Accessibility", action: requestAccessibility).buttonStyle(SecondaryButtonStyle())
                        } else {
                            HStack(spacing: 8) {
                                Button("dry run", action: model.dryRun).buttonStyle(SecondaryButtonStyle())
                                Button("run locally", action: model.runLocally).buttonStyle(PrimaryButtonStyle())
                            }

                            HStack(spacing: 8) {
                                Button("undo", action: model.undoLastRun).buttonStyle(SecondaryButtonStyle())
                                Button("request Accessibility", action: requestAccessibility).buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                } else {
                    EmptySurface(icon: "sidebar.right", title: "No node selected", detail: "Node settings will appear here.")
                }
            }
        }
        .frame(minWidth: 260, idealWidth: compact ? 300 : 344, maxWidth: 560)
        .layoutPriority(4)
    }

    private func title(for id: UUID) -> String {
        model.workflow.nodes.first(where: { $0.id == id })?.title ?? "Missing node"
    }

    private func summary(for node: WorkflowNode) -> String {
        switch node.kind {
        case .trigger: return "Starts the workflow when new screenshots appear. The demo keeps this manual until you enable background watching."
        case .findScreenshots: return "Finds matching screenshot files before anything moves. The dry run lists exact paths."
        case .reviewWarnings: return "Reviews screenshots for warning indicators locally before deciding where files should go."
        case .moveFiles: return "Moves files only after dry run and trust approval. Undo is available for the last local run."
        case .logRun: return "Appends a local run log so background work is inspectable later."
        case .accessibilityFallback: return "Requests macOS Accessibility only when UI control is needed. It never runs silently."
        case .automationAction: return "Runs this exact primitive with the displayed arguments after the executable node is approved."
        }
    }
}

private struct LogDrawer: View {
    @Bindable var model: StudioModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            PanelBackdrop(imageName: "TerminalPanelBackground", scrimOpacity: 0.10, scaleY: 0.7, offsetY: -90)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("local run logs")
                        .font(.system(size: 13).weight(.semibold))
                    Spacer()
                    HStack(spacing: 8) {
                        Toggle("workflow timer", isOn: Binding(
                            get: { !model.workflow.groupedSchedule.isEmpty },
                            set: { enabled in
                                if enabled {
                                    model.setWorkflowDaily(Date())
                                } else {
                                    model.clearWorkflowSchedule()
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(size: 11).weight(.semibold))
                        NodeSchedulePill(
                            schedule: model.workflow.groupedSchedule.isEmpty ? "Daily at \(Self.timeFormatter.string(from: Date()))" : model.workflow.groupedSchedule,
                            setDaily: model.setWorkflowDaily,
                            setOnce: model.setWorkflowRunOnce,
                            clear: model.clearWorkflowSchedule
                        )
                        .disabled(model.workflow.groupedSchedule.isEmpty)
                    }
                    Text("Stored locally")
                        .foregroundStyle(StudioPalette.muted)
                        .font(.system(size: 11).weight(.medium))
                }
                ScrollView {
                    VStack(spacing: 6) {
                        if model.logs.isEmpty {
                            Text("No local runs yet.")
                                .font(.system(size: 11, design: .monospaced).monospaced())
                                .foregroundStyle(StudioPalette.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(model.logs.prefix(7)) { log in
                                HStack(spacing: 12) {
                                    Text(log.time, style: .time)
                                        .foregroundStyle(StudioPalette.muted)
                                        .frame(width: 70, alignment: .leading)
                                    Text(log.node)
                                        .foregroundStyle(statusColor(log.status))
                                        .frame(width: 94, alignment: .leading)
                                    Text(log.message)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.system(size: 11, design: .monospaced).monospaced())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(height: 132)
        .clipped()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

private enum ScheduleCadence: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case once = "Once"

    var id: String { rawValue }
}

private struct NodeSchedulePill: View {
    var schedule: String
    var setDaily: (Date) -> Void
    var setOnce: (Date) -> Void
    var clear: () -> Void
    @State private var cadence: ScheduleCadence = .daily
    @State private var date = Date()
    @State private var popoverOpen = false

    var body: some View {
        Button {
            popoverOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                Text(displaySchedule)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10).weight(.bold))
            }
            .font(.system(size: 12).weight(.semibold))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(StudioPalette.panelStrong)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(StudioPalette.line))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $popoverOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Schedule")
                    .font(.system(size: 15).weight(.semibold))
                Picker("Schedule", selection: $cadence) {
                    ForEach(ScheduleCadence.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                DatePicker(cadence == .daily ? "Time" : "Date and time", selection: $date)
                    .datePickerStyle(.compact)
                HStack {
                    Button("off", action: {
                        clear()
                        popoverOpen = false
                    })
                    .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button("apply", action: {
                        if cadence == .daily {
                            setDaily(date)
                        } else {
                            setOnce(date)
                        }
                        popoverOpen = false
                    })
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(14)
            .frame(width: 250)
            .background(StudioPalette.panel)
        }
    }

    private var displaySchedule: String {
        if schedule == "Manual" || schedule.isEmpty { return "Off" }
        if schedule.hasPrefix("Every day at ") {
            return "Daily at \(schedule.dropFirst("Every day at ".count))"
        }
        if schedule.hasPrefix("Once: ") { return "Once" }
        return schedule
    }
}

private struct PanelBackgroundImage: View {
    var name: String
    var scale: CGFloat = 1.0
    var scaleY: CGFloat = 1.0
    var offsetY: CGFloat = 0.0

    var body: some View {
        GeometryReader { proxy in
            if let image = loadImage(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(x: scale, y: scale * scaleY, anchor: .center)
                    .offset(x: 0, y: offsetY)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        }
        .allowsHitTesting(false)
    }

    private func loadImage(named: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: named, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

/// Decorative panel backdrop behind content; must not intercept clicks.
private struct PanelBackdrop: View {
    var imageName: String
    /// Light tint so text stays readable without hiding the artwork.
    var scrimOpacity: Double
    var scale: CGFloat = 1.0
    var scaleY: CGFloat = 1.0
    var offsetY: CGFloat = 0.0

    var body: some View {
        ZStack {
            PanelBackgroundImage(
                name: imageName,
                scale: scale,
                scaleY: scaleY,
                offsetY: offsetY
            )
            Color.black.opacity(scrimOpacity)
        }
        .allowsHitTesting(false)
    }
}

private struct NodeCard: View {
    var node: WorkflowNode
    var isSelected: Bool
    var isConnectionSource: Bool
    var onSelect: () -> Void
    var onStartConnection: () -> Void
    var onFinishConnection: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                Image(systemName: iconName(for: node.kind))
                    .font(.system(size: 20).weight(.semibold))
                    .foregroundStyle(statusColor(node.status))
                Text(node.title)
                    .font(.system(size: 13).weight(.semibold))
                    .foregroundStyle(StudioPalette.text)
                Text(node.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(StudioPalette.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                RoundedRectangle(cornerRadius: 2)
                    .fill(statusColor(node.status))
                    .frame(width: 16, height: 16)
                    .overlay(Image(systemName: node.status == .warning ? "exclamationmark" : "checkmark").font(.system(size: 8).weight(.bold)).foregroundStyle(.black.opacity(0.7)))
            }
            .padding(12)
            .frame(width: 136, height: 104)
            .background(node.status == .warning ? StudioPalette.amberSoft : StudioPalette.node)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        isConnectionSource ? StudioPalette.accentBright :
                        isSelected ? StudioPalette.accentBright :
                        statusColor(node.status).opacity(0.7),
                        lineWidth: (isSelected || isConnectionSource) ? 2 : 1
                    )
            )
            .shadow(color: StudioPalette.accentBright.opacity(isSelected ? 0.18 : 0.0), radius: isSelected ? 16 : 0, x: 0, y: 0)
            .shadow(color: .black.opacity(isSelected ? 0.35 : 0.18), radius: isSelected ? 14 : 8, x: 0, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .onTapGesture(perform: onSelect)

            ConnectorButton(systemName: "arrow.right", color: StudioPalette.accentBright, action: onStartConnection)
                .offset(x: 76, y: 0)
                .help("Start connection")

            ConnectorButton(systemName: "arrow.left", color: StudioPalette.text, action: onFinishConnection)
                .offset(x: -76, y: 0)
                .help("Finish connection")
        }
        .frame(width: 156, height: 118)
    }
}

private struct ConnectorButton: View {
    var systemName: String
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(StudioPalette.canvas)
                RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.9), lineWidth: 1.5)
                Image(systemName: systemName)
                    .font(.system(size: 8).weight(.heavy))
                    .foregroundStyle(color)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }
}

private struct EdgeLine: View {
    var from: CGPoint
    var to: CGPoint
    var isFallback: Bool

    var body: some View {
        Path { path in
            path.move(to: from)
            let midX = (from.x + to.x) / 2
            path.addCurve(to: to, control1: CGPoint(x: midX, y: from.y), control2: CGPoint(x: midX, y: to.y))
        }
        .stroke(isFallback ? StudioPalette.amber : StudioPalette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: isFallback ? [5, 5] : []))
    }
}

private struct EdgeDeleteButton: View {
    var isFallback: Bool
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(StudioPalette.canvas.opacity(0.96))
                RoundedRectangle(cornerRadius: 3).stroke(isFallback ? StudioPalette.amber : StudioPalette.accentBright, lineWidth: isHovering ? 2 : 1.4)
                Image(systemName: "xmark")
                    .font(.system(size: 8).weight(.heavy))
                    .foregroundStyle(isHovering ? StudioPalette.text : StudioPalette.muted)
            }
            .frame(width: isHovering ? 26 : 22, height: isHovering ? 26 : 22)
            .shadow(color: .black.opacity(isHovering ? 0.28 : 0.16), radius: isHovering ? 8 : 4, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Reactive Dotted Background

private struct ReactiveBackgroundContainer<Content: View>: View {
    @State private var mousePosition: CGPoint = .init(x: -1000, y: -1000)
    var color: Color
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            color
            ReactiveDottedBackground(mousePosition: mousePosition)
            content
        }
        .background(
            MouseTrackingView(mouseLocation: $mousePosition)
        )
    }
}

private struct ReactiveDottedBackground: View {
    var mousePosition: CGPoint

    var body: some View {
        Canvas { context, size in
            let dotSpacing: CGFloat = 24
            let dotSize: CGFloat = 1.6

            let columns = Int(size.width / dotSpacing) + 1
            let rows = Int(size.height / dotSpacing) + 1

            for row in 0..<rows {
                for col in 0..<columns {
                    let centerX = CGFloat(col) * dotSpacing
                    let centerY = CGFloat(row) * dotSpacing
                    let center = CGPoint(x: centerX, y: centerY)

                    let dist = sqrt(pow(center.x - mousePosition.x, 2) + pow(center.y - mousePosition.y, 2))
                    let maxDist: CGFloat = 160
                    let intensity = max(0, 1 - (dist / maxDist))

                    let scale = 1.0 + intensity * 1.8
                    let currentSize = dotSize * scale

                    let rect = CGRect(
                        x: centerX - currentSize/2,
                        y: centerY - currentSize/2,
                        width: currentSize,
                        height: currentSize
                    )

                    let opacity = 0.24 + (intensity * 0.30)
                    context.opacity = opacity
                    context.fill(Path(ellipseIn: rect), with: .color(StudioPalette.accent))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MouseTrackingView: NSViewRepresentable {
    @Binding var mouseLocation: CGPoint

    func makeNSView(context: Context) -> NSView {
        let view = MouseView()
        view.onLocationChange = { location in
            self.mouseLocation = location
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class MouseView: NSView {
        var onLocationChange: ((CGPoint) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas {
                removeTrackingArea(area)
            }
            let options: NSTrackingArea.Options = [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect]
            let area = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
        }

        override func mouseMoved(with event: NSEvent) {
            onLocationChange?(canvasLocation(for: event))
        }

        override func mouseEntered(with event: NSEvent) {
            onLocationChange?(canvasLocation(for: event))
        }

        override func mouseExited(with event: NSEvent) {
            onLocationChange?(.init(x: -1000, y: -1000))
        }

        private func canvasLocation(for event: NSEvent) -> CGPoint {
            let location = convert(event.locationInWindow, from: nil)
            return CGPoint(x: location.x, y: bounds.height - location.y)
        }
    }
}

// MARK: - Warping Spacetime Grid

private struct WarpingGridBackground: View {
    @State private var mousePosition: CGPoint = .init(x: -1000, y: -1000)
    var nodes: [WorkflowNode]

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 32
            let cols = Int(size.width / spacing) + 1
            let rows = Int(size.height / spacing) + 1
            let warpStrength: CGFloat = 28.0
            let warpRadius: CGFloat = 180.0
            let mouseWarpStrength: CGFloat = 34.0
            let mouseWarpRadius: CGFloat = 210.0

            let nodePositions = nodes.map { CGPoint(x: $0.x + 68, y: $0.y + 52) }

            func warpedPoint(_ gridX: CGFloat, _ gridY: CGFloat) -> CGPoint {
                var dx: CGFloat = 0
                var dy: CGFloat = 0
                for np in nodePositions {
                    let diffX = gridX - np.x
                    let diffY = gridY - np.y
                    let dist = sqrt(diffX * diffX + diffY * diffY)
                    if dist < warpRadius && dist > 1 {
                        let force = warpStrength * (1.0 - dist / warpRadius) * (1.0 - dist / warpRadius)
                        dx -= (diffX / dist) * force
                        dy -= (diffY / dist) * force
                    }
                }

                let mouseDiffX = gridX - mousePosition.x
                let mouseDiffY = gridY - mousePosition.y
                let mouseDist = sqrt(mouseDiffX * mouseDiffX + mouseDiffY * mouseDiffY)
                if mouseDist < mouseWarpRadius && mouseDist > 1 {
                    let force = mouseWarpStrength * (1.0 - mouseDist / mouseWarpRadius) * (1.0 - mouseDist / mouseWarpRadius)
                    dx -= (mouseDiffX / mouseDist) * force
                    dy -= (mouseDiffY / mouseDist) * force
                }

                return CGPoint(x: gridX + dx, y: gridY + dy)
            }

            for row in 0...rows {
                var hPath = Path()
                let y = CGFloat(row) * spacing
                let firstPt = warpedPoint(0, y)
                hPath.move(to: firstPt)
                for col in 1...cols {
                    let x = CGFloat(col) * spacing
                    let pt = warpedPoint(x, y)
                    hPath.addLine(to: pt)
                }
                context.stroke(hPath, with: .color(StudioPalette.grid), lineWidth: 0.5)
            }

            for col in 0...cols {
                var vPath = Path()
                let x = CGFloat(col) * spacing
                let firstPt = warpedPoint(x, 0)
                vPath.move(to: firstPt)
                for row in 1...rows {
                    let y = CGFloat(row) * spacing
                    let pt = warpedPoint(x, y)
                    vPath.addLine(to: pt)
                }
                context.stroke(vPath, with: .color(StudioPalette.grid), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
        .background(
            MouseTrackingView(mouseLocation: $mousePosition)
        )
    }
}

private struct MiniMap: View {
    var nodes: [WorkflowNode]
    var edges: [WorkflowEdge]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.25))
            RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line)
            ForEach(nodes) { node in
                RoundedRectangle(cornerRadius: 1)
                    .fill(statusColor(node.status))
                    .frame(width: 16, height: 10)
                    .position(x: node.x / 8 + 14, y: node.y / 8 + 14)
            }
        }
        .frame(width: 138, height: 74)
        .allowsHitTesting(false)
    }
}

private struct Bubble: View {
    var text: String
    var sender: String
    var alignRight: Bool

    var body: some View {
        VStack(alignment: alignRight ? .trailing : .leading, spacing: 6) {
            Text(sender)
                .font(.system(size: 10).weight(.bold))
                .foregroundStyle(StudioPalette.muted)
            MarkdownText(text)
                .font(.system(size: 13))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: alignRight ? .trailing : .leading)
        .background(alignRight ? StudioPalette.userBubble : StudioPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
    }
}

private struct MarkdownText: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .blank:
                    Spacer(minLength: 8)
                case .heading(let level, let content):
                    Text(inlineMarkdown(content))
                        .font(headingFont(level))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, level == 1 ? 4 : 2)
                case .bullet(let content):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(inlineMarkdown(content))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .numbered(let number, let content):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(number).")
                            .frame(minWidth: 22, alignment: .trailing)
                        Text(inlineMarkdown(content))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .paragraph(let content):
                    Text(inlineMarkdown(content))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var blocks: [MarkdownBlock] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { MarkdownBlock(String($0)) }
    }

    private func inlineMarkdown(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return StudioType.sectionTitle
        case 2: return StudioType.cardTitle
        default: return StudioType.body.weight(.semibold)
        }
    }
}

private enum MarkdownBlock {
    case blank
    case heading(level: Int, content: String)
    case bullet(content: String)
    case numbered(number: Int, content: String)
    case paragraph(content: String)

    init(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            self = .blank
            return
        }
        let headingPrefix = line.prefix(while: { $0 == "#" })
        if !headingPrefix.isEmpty,
           headingPrefix.count <= 6,
           line.dropFirst(headingPrefix.count).first == " " {
            self = .heading(level: headingPrefix.count, content: String(line.dropFirst(headingPrefix.count + 1)))
            return
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            self = .bullet(content: String(line.dropFirst(2)))
            return
        }
        if let dot = line.firstIndex(of: "."),
           let number = Int(line[..<dot]),
           line[line.index(after: dot)...].first == " " {
            self = .numbered(number: number, content: String(line[line.index(line.startIndex, offsetBy: String(number).count + 2)...]))
            return
        }
        self = .paragraph(content: line)
    }
}

private struct AutomationRow: View {
    var title: String
    var subtitle: String
    var active: Bool

    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 1).fill(active ? StudioPalette.accent : StudioPalette.muted).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13).weight(.semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(StudioPalette.muted)
            }
            Spacer()
        }
        .padding(10)
        .background(active ? StudioPalette.accentSoft : StudioPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(active ? StudioPalette.accent.opacity(0.65) : StudioPalette.line))
    }
}

private struct InspectorSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11).weight(.bold))
                .tracking(0.5)
                .foregroundStyle(StudioPalette.muted)
            content
        }
    }
}

private struct ConnectionRow: View {
    var edge: WorkflowEdge
    var fromTitle: String
    var toTitle: String
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: edge.isFallback ? "arrow.triangle.branch" : "arrow.right")
                .foregroundStyle(edge.isFallback ? StudioPalette.amber : StudioPalette.accentBright)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(fromTitle) -> \(toTitle)")
                    .font(.system(size: 12).weight(.semibold))
                    .lineLimit(1)
                Text(edge.isFallback ? "Fallback path" : "Main path")
                    .font(.system(size: 11))
                    .foregroundStyle(StudioPalette.muted)
            }

            Spacer()

            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10).weight(.bold))
            }
            .buttonStyle(IconButtonStyle())
            .frame(width: 30, height: 30)
        }
        .padding(10)
        .background(StudioPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
    }
}

private struct ParameterRow: View {
    var key: String
    var value: String

    var body: some View {
        HStack {
            Text(key).foregroundStyle(StudioPalette.muted)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.system(size: 12))
        .padding(10)
        .background(StudioPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

private struct ImpactRow: View {
    var item: ImpactItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.action.uppercased())
                .font(.system(size: 10).weight(.bold))
                .foregroundStyle(StudioPalette.accentBright)
            Text(item.source)
                .font(.system(size: 11, design: .monospaced).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Text(item.destination)
                .font(.system(size: 11, design: .monospaced).monospaced())
                .foregroundStyle(StudioPalette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

private struct AppIconImage: View {
    var body: some View {
        if let image = AppAssets.icon {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 6).fill(StudioPalette.accentSoft)
                .overlay(Image(systemName: "point.3.connected.trianglepath.dotted").font(.largeTitle))
        }
    }
}

enum AppAssets {
    static var icon: NSImage? {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

enum PetAssets {
    static var spritesheet: NSImage? {
        guard let url = Bundle.module.url(forResource: "CurryDogSpritesheet", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

// MARK: - Nex — the automation builder mascot

private struct NexPetFrameView: View {
    let col: Int
    let row: Int
    let scale: CGFloat

    var body: some View {
        if let image = PetAssets.spritesheet {
            Image(nsImage: image)
                .resizable()
                .frame(width: 1536 * scale, height: 1872 * scale)
                .offset(x: -CGFloat(col) * 192 * scale, y: -CGFloat(row) * 208 * scale)
                .frame(width: 192 * scale, height: 208 * scale, alignment: .topLeading)
                .clipped()
        } else {
            Color.clear
                .frame(width: 192 * scale, height: 208 * scale)
        }
    }
}

private struct NexPetView: View {
    @Bindable var model: StudioModel
    @State private var currentFrame = 0
    @State private var activeRow = 0
    @State private var isWaving = false
    @State private var waveTimer: Timer? = nil
    @State private var isHovering = false

    let timer = Timer.publish(every: 0.18, on: .main, in: .common).autoconnect()
    let petScale: CGFloat = 0.55

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                NexPetFrameView(col: currentFrame, row: activeRow, scale: petScale)
                    .frame(width: 192 * petScale, height: 208 * petScale)
                    .scaleEffect(isHovering ? 1.06 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
            }
            .frame(maxWidth: .infinity)
            .onTapGesture {
                isWaving = true
                currentFrame = 0
                activeRow = 3
                waveTimer?.invalidate()
                waveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    isWaving = false
                }
            }
            .onHover { isHovering = $0 }

            Text("NEX")
                .font(StudioType.brandWordmark)
                .tracking(2)
                .foregroundStyle(StudioPalette.accentBright)
                .padding(.top, 4)

            Text(statusMessage)
                .font(StudioType.secondary)
                .foregroundStyle(StudioPalette.text)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(StudioPalette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(isHovering ? StudioPalette.accentBright.opacity(0.4) : StudioPalette.line, lineWidth: 1))
                .padding(.top, 6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(StudioPalette.panel.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(isHovering ? StudioPalette.accentBright.opacity(0.3) : StudioPalette.line.opacity(0.5), lineWidth: 1))
        )
        .shadow(color: StudioPalette.accentBright.opacity(isHovering ? 0.08 : 0.0), radius: 12, x: 0, y: 0)
        .onReceive(timer) { _ in
            let row = currentAnimationRow()
            if row != activeRow {
                activeRow = row
                currentFrame = 0
            } else {
                currentFrame = (currentFrame + 1) % frameCount(for: row)
            }
        }
    }

    private var statusMessage: String {
        if isWaving { return "oh good, you're here" }
        if model.isGenerating || model.runnerStatus == "Generating" { return "hold on, i'm doing my little thinking dance..." }
        if model.isRunning || model.runnerStatus == "Running" { return "okay okay it's happening, watch the nodes light up!" }
        if model.runnerStatus == "Failed" || model.runnerStatus == "Generation failed" { return "well that was embarrassing" }
        if model.runnerStatus == "Complete" { return "boom. nailed it." }
        if model.approvalRequired || model.runnerStatus == "Generated" || model.runnerStatus == "Loaded" { return "looks pretty good, trust me" }
        return "chilling... just tell me what chaos we're automating today"
    }

    private func currentAnimationRow() -> Int {
        if isWaving { return 3 }
        if model.isGenerating || model.runnerStatus == "Generating" { return 6 }
        if model.isRunning || model.runnerStatus == "Running" { return 7 }
        if model.runnerStatus == "Failed" || model.runnerStatus == "Generation failed" { return 5 }
        if model.runnerStatus == "Complete" { return 4 }
        if model.approvalRequired || model.runnerStatus == "Generated" || model.runnerStatus == "Loaded" { return 8 }
        return 0
    }

    private func frameCount(for row: Int) -> Int {
        switch row {
        case 0: return 6
        case 1, 2: return 8
        case 3: return 4
        case 4: return 5
        case 5: return 8
        case 6, 7, 8: return 6
        default: return 6
        }
    }
}

@MainActor
private struct FloatingNexOverlay: View {
    @Bindable var model: StudioModel
    @Bindable var voice: NexVoiceStore
    @State private var offset = CGSize.zero
    @State private var dragOrigin = CGSize.zero
    @State private var petScale: CGFloat = 1.05
    @State private var petScaleOrigin: CGFloat = 1.05

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                MarkdownText(voice.transcriber.isRecording ? (voice.transcriber.transcript.isEmpty ? "Listening..." : voice.transcriber.transcript) : voice.response)
                    .font(StudioType.body)
                    .padding(10)
                    .frame(width: 330, alignment: .leading)
                    .background(StudioPalette.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.line))
                Button {
                    voice.isVisible = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButtonStyle())
            }
            HStack(spacing: 8) {
                Button {
                    voice.toggle(using: model)
                } label: {
                    Image(systemName: voice.transcriber.isRecording ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(IconButtonStyle())
                ZStack(alignment: .bottomTrailing) {
                    FloatingAnimatedNexPet(model: model, voice: voice, petScale: petScale)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10).weight(.bold))
                        .foregroundStyle(StudioPalette.accentBright)
                        .padding(4)
                        .background(StudioPalette.panel)
                        .clipShape(Circle())
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    petScale = min(max(petScaleOrigin + value.translation.width / 320, 0.35), 1.35)
                                }
                                .onEnded { _ in petScaleOrigin = petScale }
                        )
                }
            }
        }
        .padding(10)
        .background(StudioPalette.panel.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    offset = CGSize(width: dragOrigin.width + value.translation.width, height: dragOrigin.height + value.translation.height)
                }
                .onEnded { _ in dragOrigin = offset }
        )
    }
}

@MainActor
private struct FloatingAnimatedNexPet: View {
    @Bindable var model: StudioModel
    @Bindable var voice: NexVoiceStore
    var petScale: CGFloat
    @State private var currentFrame = 0
    @State private var activeRow = 0
    @State private var isWaving = false
    @State private var waveTimer: Timer?
    @State private var isHovering = false

    private let timer = Timer.publish(every: 0.18, on: .main, in: .common).autoconnect()

    var body: some View {
        NexPetFrameView(col: currentFrame, row: activeRow, scale: petScale)
            .frame(width: 192 * petScale, height: 208 * petScale)
            .scaleEffect(isHovering ? 1.06 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
            .contentShape(Rectangle())
            .onTapGesture {
                isWaving = true
                currentFrame = 0
                activeRow = 3
                waveTimer?.invalidate()
                waveTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
                    Task { @MainActor in isWaving = false }
                }
            }
            .onHover { isHovering = $0 }
            .onReceive(timer) { _ in
                let row = animationRow
                if row != activeRow {
                    activeRow = row
                    currentFrame = 0
                } else {
                    currentFrame = (currentFrame + 1) % frameCount(for: row)
                }
            }
    }

    private var animationRow: Int {
        if isWaving { return 3 }
        if voice.transcriber.isRecording { return 7 }
        if model.isGenerating || model.runnerStatus == "Generating" { return 6 }
        if model.isRunning || model.runnerStatus == "Running" { return 7 }
        if model.runnerStatus == "Failed" || model.runnerStatus == "Generation failed" { return 5 }
        if model.runnerStatus == "Complete" { return 4 }
        if model.approvalRequired || model.runnerStatus == "Generated" || model.runnerStatus == "Loaded" { return 8 }
        return 0
    }

    private func frameCount(for row: Int) -> Int {
        switch row {
        case 3: return 4
        case 4: return 5
        case 5: return 8
        default: return 6
        }
    }
}

enum StudioType {
    static let brandWordmark = FontStacks.main(size: 14).weight(.bold)
    static let pageTitle = FontStacks.main(size: 32).weight(.bold)
    static let sectionTitle = FontStacks.main(size: 24).weight(.semibold)
    static let cardTitle = FontStacks.main(size: 18).weight(.semibold)
    static let body = FontStacks.main(size: 14).weight(.regular)
    static let secondary = FontStacks.main(size: 12).weight(.regular)
    static let metadata = FontStacks.main(size: 11).weight(.medium)
    static let button = FontStacks.main(size: 14).weight(.medium)
    static let code = FontStacks.mono(size: 11).weight(.regular)

    static let echoTitle = FontStacks.echo(size: 32).weight(.bold)
    static let echoCardTitle = FontStacks.echo(size: 18).weight(.semibold)
    static let echoBody = FontStacks.echo(size: 14).weight(.regular)
    static let echoSecondary = FontStacks.echo(size: 12).weight(.regular)
    static let echoMetadata = FontStacks.echo(size: 11).weight(.medium)
}

private enum FontStacks {
    private static let mainNames = [
        "Sohne",
        "Söhne",
        "Sohne-Regular",
        "Söhne-Regular",
        "Geist",
        "Geist-Regular",
        "Instrument Serif",
        "InstrumentSerif-Regular"
    ]
    private static let echoNames = [
        "Instrument Serif",
        "InstrumentSerif-Regular",
        "InstrumentSerif",
        "Sohne",
        "Söhne",
        "Geist"
    ]
    private static let monoNames = [
        "Berkeley Mono",
        "BerkeleyMono-Regular",
        "BerkeleyMono",
        "Geist Mono",
        "GeistMono-Regular",
        "Menlo"
    ]

    static func main(size: CGFloat) -> Font {
        resolvedFont(names: mainNames, size: size, fallback: .system(size: size))
    }

    static func echo(size: CGFloat) -> Font {
        resolvedFont(names: echoNames, size: size, fallback: .system(size: size, design: .serif))
    }

    static func mono(size: CGFloat) -> Font {
        resolvedFont(names: monoNames, size: size, fallback: .system(size: size, design: .monospaced))
    }

    private static func resolvedFont(names: [String], size: CGFloat, fallback: Font) -> Font {
        if let installed = names.first(where: { NSFont(name: $0, size: size) != nil }) {
            return .custom(installed, fixedSize: size)
        }
        return fallback
    }
}

// MARK: - Button Styles — Geometric / Angular

private struct CanvasTabButtonStyle: ButtonStyle {
    var isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11).weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(isSelected ? StudioPalette.panelStrong.opacity(configuration.isPressed ? 0.8 : 1) : Color.clear)
            .foregroundStyle(isSelected ? StudioPalette.text : StudioPalette.muted)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(StudioType.button)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(isEnabled ? StudioPalette.accentButton.opacity(configuration.isPressed ? 0.8 : 1) : StudioPalette.panel)
            .foregroundStyle(isEnabled ? .white : StudioPalette.muted)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(isEnabled ? StudioPalette.accentBright.opacity(0.3) : .clear, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.58)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(StudioType.button)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(StudioPalette.panel.opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.5))
            .foregroundStyle(isEnabled ? StudioPalette.text : StudioPalette.muted)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
            .opacity(isEnabled ? 1 : 0.58)
    }
}

private struct TrustButtonStyle: ButtonStyle {
    var disabledLook: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13).weight(.bold))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(disabledLook ? StudioPalette.accentSoft.opacity(0.45) : StudioPalette.accentSoft)
            .foregroundStyle(StudioPalette.accentBright)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.accent.opacity(0.7)))
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 34, height: 30)
            .background(StudioPalette.panel.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
            .contentShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

private struct StatusPill: View {
    var label: String, value: String, color: Color
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 7, height: 7)
            Text(label + ":").foregroundStyle(StudioPalette.muted)
            Text(value)
        }
        .font(.system(size: 12).weight(.semibold))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(StudioPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
    }
}

private func iconName(for kind: NodeKind) -> String {
    switch kind {
    case .trigger: return "bolt.fill"
    case .findScreenshots: return "folder"
    case .reviewWarnings: return "exclamationmark.triangle"
    case .moveFiles: return "folder.badge.gearshape"
    case .logRun: return "doc.text"
    case .accessibilityFallback: return "figure.arms.open"
    case .automationAction: return "gearshape.2"
    }
}

private func statusColor(_ status: NodeStatus) -> Color {
    switch status {
    case .idle: return StudioPalette.muted
    case .ready: return StudioPalette.accent
    case .warning: return StudioPalette.amber
    case .success: return StudioPalette.accentBright
    case .blocked: return StudioPalette.red
    }
}

enum StudioPalette {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.06)
    static let chrome = Color(red: 0.07, green: 0.07, blue: 0.075)
    static let sidebar = Color(red: 0.045, green: 0.045, blue: 0.05)
    static let canvas = Color(red: 0.06, green: 0.06, blue: 0.065)
    static let inspector = Color(red: 0.075, green: 0.075, blue: 0.08)
    static let panel = Color.white.opacity(0.06)
    static let panelStrong = Color.white.opacity(0.10)
    static let node = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let userBubble = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let text = Color(red: 0.92, green: 0.93, blue: 0.94)
    static let muted = Color(red: 0.52, green: 0.54, blue: 0.56)
    static let line = Color.white.opacity(0.12)
    static let grid = Color(red: 0.30, green: 0.55, blue: 0.55).opacity(0.25)
    static let accent = Color(red: 0.70, green: 0.75, blue: 0.80)
    static let accentBright = Color(red: 0.88, green: 0.92, blue: 0.96)
    static let accentSoft = Color(red: 0.20, green: 0.22, blue: 0.25).opacity(0.42)
    static let accentButton = Color(red: 0.30, green: 0.32, blue: 0.36)
    static let amber = Color(red: 0.93, green: 0.63, blue: 0.25)
    static let amberSoft = Color(red: 0.35, green: 0.25, blue: 0.12)
    static let red = Color(red: 0.92, green: 0.36, blue: 0.31)
    static let code = Color(red: 0.72, green: 0.80, blue: 0.88)
    static let codeBackground = Color.black.opacity(0.35)
}
