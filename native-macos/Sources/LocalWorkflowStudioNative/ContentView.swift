import SwiftUI
import AppKit
import ApplicationServices
import LocalWorkflowStudioCore

struct ContentView: View {
    @Bindable var model: StudioModel
    @State private var walkthroughOpen = false
    @State private var walkthroughStepIndex = 0

    var body: some View {
        GeometryReader { proxy in
            shell(compact: proxy.size.width < 1360)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .foregroundStyle(StudioPalette.text)
        .task {
            await model.refreshSavedNodes()
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
                    Sidebar(model: model, compact: compact)
                    PromptPanel(model: model, compact: compact)
                    CanvasPanel(model: model, compact: compact)
                    InspectorPanel(model: model, compact: compact) {
                        requestAccessibilityPermission()
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

private struct TitleBar: View {
    @Bindable var model: StudioModel
    var onOpenWalkthrough: () -> Void

    var body: some View {
        ZStack {
            PanelBackdrop(imageName: "TitleBarBackground", scrimOpacity: 0.55, scaleY: 0.65)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Text("NEXUS")
                    .font(.system(size: 14, weight: .heavy, design: .default))
                    .tracking(2)
                    .foregroundStyle(StudioPalette.text)
                Spacer()
                StatusPill(label: "meeting", value: model.lifePlan == nil ? "ready" : "briefed", color: model.lifePlan == nil ? StudioPalette.muted : StudioPalette.accent)
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
            title: "Paste a transcript",
            detail: "Start with meeting transcripts, notes, school tasks, links, or messy plans. Nexus turns the intake into a command brief before building any workflow.",
            checks: [
                "Paste one block of context",
                "Plan creates the brief",
                "Build converts one suggestion into a canvas"
            ]
        ),
        WalkthroughStep(
            id: "canvas",
            icon: "point.3.connected.trianglepath.dotted",
            title: "Edit the control canvas",
            detail: "The canvas works like an n8n-style editor for the automations you approve: drag nodes around, connect outputs to inputs, and delete wires directly.",
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
            detail: "Nexus blocks execution until the exact workflow version is trusted. If your assistant plan changes scripts, permissions, or wires, approval is required again.",
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
                            .font(.system(size: 13, weight: .bold))
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
                            .font(.system(size: 11, weight: .bold))
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
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(StudioPalette.accentBright)
                        }
                        .frame(width: 54, height: 54)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(activeStep.title)
                                .font(.system(size: 23, weight: .bold))
                            Text(activeStep.detail)
                                .font(.system(size: 14))
                                .foregroundStyle(StudioPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(activeStep.checks, id: \.self) { check in
                            Label(check, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .medium))
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
                        .font(.system(size: 11, weight: .bold))
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
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(active ? StudioPalette.accentBright : StudioPalette.panelStrong)
                    .foregroundStyle(active ? Color.black.opacity(0.85) : StudioPalette.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(step.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(step.id.capitalized)
                        .font(.system(size: 10, weight: .medium))
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
                            .font(.system(size: 13, weight: .heavy))
                            .tracking(2)
                        Text("meeting assistant")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(StudioPalette.muted)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, compact ? 2 : 10)

                SidebarButton(icon: "tray.full", label: "meeting inbox", active: true, compact: compact)
                SidebarButton(icon: "point.3.connected.trianglepath.dotted", label: "workflow builder", active: false, compact: compact)
                SidebarButton(icon: "clock", label: "runs", active: false, compact: compact)
                SidebarButton(icon: "gearshape", label: "settings", active: false, compact: compact)

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
                        Text("~/Nexus")
                            .foregroundStyle(StudioPalette.accent)
                            .font(.custom("Berkeley Mono", size: 11, relativeTo: .caption).monospaced())
                    }
                    .font(.system(size: 12, weight: .medium))
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
            .font(.system(size: 14, weight: .medium))
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
                    Text("meeting command inbox")
                        .font(.system(size: 16, weight: .bold))
                    Text("paste transcripts, notes, dates, links, or plans")
                        .font(.system(size: 12))
                        .foregroundStyle(StudioPalette.muted)
                }

                if let plan = model.lifePlan {
                    LifePlanCard(plan: plan, build: model.buildWorkflow)
                } else if model.hasWorkflow {
                    VStack(alignment: .leading, spacing: 10) {
                        Bubble(text: model.workflow.prompt, sender: "You", alignRight: true)
                        Bubble(text: "Generated executable runner steps with the local model.", sender: "Local AI", alignRight: false)
                    }
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.prompt)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(10)

                    if model.prompt.isEmpty {
                        Text("Paste a transcript, meeting notes, tasks, links, or a messy plan")
                            .font(.system(size: 13))
                            .foregroundStyle(StudioPalette.muted)
                            .padding(.horizontal, 15)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: model.lifePlan == nil && !model.hasWorkflow ? 168 : 118)
                .background(StudioPalette.panelStrong)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button(action: model.createLifePlan) {
                            Label(model.isPlanning ? "planning" : "plan", systemImage: "sparkles")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!model.canCreateLifePlan)
                        Button(action: {
                            if model.lifePlan == nil {
                                model.generateWorkflow()
                            } else {
                                model.buildWorkflowFromLifePlan()
                            }
                        }) {
                            Label(model.lifePlan == nil ? "generate" : "build flow", systemImage: "point.3.connected.trianglepath.dotted")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.lifePlan == nil ? !model.canGenerate : model.topAutomationIntent == nil)
                    }

                    Button(action: model.dryRun) {
                        Label("dry run", systemImage: "play")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!model.hasWorkflow)
                }

                if model.hasWorkflow {
                    Text("current automation")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StudioPalette.muted)
                        .padding(.top, 4)

                    AutomationRow(title: model.workflow.name, subtitle: "Generated from meeting context", active: true)
                }

                if let output = model.workflow.executionOutput {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("task completed", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(StudioPalette.accentBright)
                        Text(output)
                            .font(.custom("Berkeley Mono", size: 11, relativeTo: .caption).monospaced())
                            .textSelection(.enabled)
                            .lineLimit(6)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudioPalette.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.accent.opacity(0.8)))
                }

                Spacer()

                AssistantPetsView(model: model)
            }
            .padding(.horizontal, compact ? 14 : 20)
            .padding(.vertical, 18)
        }
        .frame(minWidth: 244, idealWidth: compact ? 286 : 324, maxWidth: 520)
        .layoutPriority(3)
    }
}

private struct LifePlanCard: View {
    var plan: LifePlan
    var build: (LifeAutomation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Label(plan.title, systemImage: "tray.full")
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Spacer()
                StatusPill(label: "date", value: plan.date, color: StudioPalette.muted)
            }

            Text(plan.brief)
                .font(.system(size: 12))
                .foregroundStyle(StudioPalette.muted)
                .lineLimit(4)

            HStack(spacing: 8) {
                MiniMetric(label: "tasks", value: "\(plan.stats.tasks)")
                MiniMetric(label: "questions", value: "\(plan.stats.questions)")
                MiniMetric(label: "links", value: "\(plan.stats.resources)")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Next Actions".uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(StudioPalette.muted)
                ForEach(Array(plan.tasks.prefix(3))) { task in
                    Label(task.title, systemImage: task.priority == "high" ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(task.priority == "high" ? StudioPalette.amber : StudioPalette.text)
                        .lineLimit(1)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Assistant Automations".uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(StudioPalette.muted)
                ForEach(Array(plan.automations.prefix(3))) { automation in
                    Button {
                        build(automation)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: automation.riskLevel == "low" ? "doc.badge.gearshape" : "safari")
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(automation.title)
                                    .font(.system(size: 12, weight: .bold))
                                Text(automation.impact)
                                    .font(.system(size: 10))
                                    .foregroundStyle(StudioPalette.muted)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(10)
                        .background(StudioPalette.panelStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
                    }
                    .buttonStyle(.plain)
                    .help("Build this suggested automation")
                }
            }
        }
        .padding(12)
        .background(StudioPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
    }
}

private struct MiniMetric: View {
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(StudioPalette.accentBright)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(StudioPalette.muted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(StudioPalette.panelStrong)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
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
                    .font(.system(size: 12, weight: .medium))
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
                                        title: "Nexus Canvas",
                                        detail: "turn meeting context into approved local workflows"
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
                                                    .font(.system(size: 13, weight: .bold))
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
                                    .font(.system(size: 16, weight: .semibold))
                                Spacer()
                                StatusPill(
                                    label: "trust",
                                    value: model.approvalRequired ? "review" : "trusted",
                                    color: model.approvalRequired ? StudioPalette.amber : StudioPalette.accent
                                )
                            }

                            Text(model.workflow.rawScript)
                                .font(.custom("Berkeley Mono", size: 13, relativeTo: .body).monospaced())
                                .foregroundStyle(StudioPalette.code)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(StudioPalette.codeBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
                                .textSelection(.enabled)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Warnings".uppercased())
                                    .font(.system(size: 11, weight: .bold))
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

                            Text("Raw scripts stay visible. Nexus still uses dry-run and trust approval gates before a local run.")
                                .font(.system(size: 12, weight: .medium))
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
                        Label("workflow run timeline", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .semibold))
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
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(statusColor(log.status))
                                    Text(log.time, style: .time)
                                        .font(.custom("Berkeley Mono", size: 11, relativeTo: .caption).monospaced())
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
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Button {
                            Task { await model.refreshSavedNodes() }
                        } label: {
                            Label("refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    Text("Generated executable nodes saved by the local backend. Load one to inspect, trust, and run it again.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(StudioPalette.muted)

                    if model.savedNodes.isEmpty {
                        EmptySurface(icon: "square.stack.3d.up", title: "No saved nodes yet", detail: "Generate a workflow and it will appear here.")
                            .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        ForEach(model.savedNodes, id: \.id) { node in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: "gearshape.2")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(StudioPalette.accentBright)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(node.meta.label)
                                        .font(.system(size: 14, weight: .bold))
                                    Text("\(node.meta.app) / \(node.meta.category) / \(node.runner.steps.count) step(s)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(StudioPalette.muted)
                                    Text(node.runner.steps.map(\.primitive).joined(separator: "  ->  "))
                                        .font(.custom("Berkeley Mono", size: 11, relativeTo: .caption).monospaced())
                                        .foregroundStyle(StudioPalette.code)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Button("Load") {
                                    model.loadSavedNode(node)
                                }
                                .buttonStyle(PrimaryButtonStyle())
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
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(StudioPalette.accentBright)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
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
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(node.status.rawValue)
                            .font(.system(size: 11, weight: .semibold))
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

                            InspectorSection(title: "Affected Local Actions") {
                                VStack(spacing: 8) {
                                    ForEach(model.workflow.impacts) { item in
                                        ImpactRow(item: item)
                                    }
                                }
                            }

                            InspectorSection(title: "Raw Script") {
                                Text(model.workflow.rawScript)
                                    .font(.custom("Berkeley Mono", size: 11, relativeTo: .caption).monospaced())
                                    .foregroundStyle(StudioPalette.code)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(StudioPalette.codeBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            }

                            if let output = model.workflow.executionOutput {
                                InspectorSection(title: "Last Output") {
                                    Text(output)
                                        .font(.custom("Berkeley Mono", size: 11, relativeTo: .caption).monospaced())
                                        .foregroundStyle(StudioPalette.accentBright)
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text("workflow run logs")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("Stored locally")
                        .foregroundStyle(StudioPalette.muted)
                        .font(.system(size: 11, weight: .medium))
                }
                ScrollView {
                    VStack(spacing: 6) {
                        if model.logs.isEmpty {
                            Text("No workflow runs yet.")
                                .font(.custom("Berkeley Mono", size: 11, relativeTo: .caption).monospaced())
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
                                .font(.custom("Berkeley Mono", size: 11, relativeTo: .caption).monospaced())
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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(statusColor(node.status))
                Text(node.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StudioPalette.text)
                Text(node.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(StudioPalette.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                RoundedRectangle(cornerRadius: 2)
                    .fill(statusColor(node.status))
                    .frame(width: 16, height: 16)
                    .overlay(Image(systemName: node.status == .warning ? "exclamationmark" : "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.black.opacity(0.7)))
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
                    .font(.system(size: 8, weight: .heavy))
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
                    .font(.system(size: 8, weight: .heavy))
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
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(StudioPalette.muted)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(StudioPalette.text)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: alignRight ? .trailing : .leading)
        .background(alignRight ? StudioPalette.userBubble : StudioPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(StudioPalette.line))
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
                Text(title).font(.system(size: 13, weight: .semibold))
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
                .font(.system(size: 11, weight: .bold))
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
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(edge.isFallback ? "Fallback path" : "Main path")
                    .font(.system(size: 11))
                    .foregroundStyle(StudioPalette.muted)
            }

            Spacer()

            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
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
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(StudioPalette.accentBright)
            Text(item.source)
                .font(.custom("Berkeley Mono", size: 11, relativeTo: .caption).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Text(item.destination)
                .font(.custom("Berkeley Mono", size: 11, relativeTo: .caption).monospaced())
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

// MARK: - Assistant pets

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

private struct AssistantPetsView: View {
    @Bindable var model: StudioModel
    @State private var currentFrame = 0
    @State private var activeRow = 0
    @State private var isWaving = false
    @State private var waveTimer: Timer? = nil
    @State private var isHovering = false

    let timer = Timer.publish(every: 0.18, on: .main, in: .common).autoconnect()
    let petScale: CGFloat = 0.55

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 4) {
                NexPetFrameView(col: currentFrame, row: activeRow, scale: petScale)
                    .frame(width: 192 * petScale, height: 208 * petScale)
                    .scaleEffect(isHovering ? 1.06 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)

                Text("NEX")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(StudioPalette.accentBright)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
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
            .help("Tap Nex")

            PetSpeechBubble(title: speechTitle, message: statusMessage, highlighted: isHovering)

            HStack(spacing: 8) {
                PetStatusBuddy(label: "plan", row: 4, col: 1, active: model.isPlanning || model.lifePlan != nil)
                PetStatusBuddy(label: "build", row: 8, col: 2, active: model.isGenerating || model.hasWorkflow)
                PetStatusBuddy(label: "run", row: 7, col: 0, active: model.isRunning || model.runnerStatus == "Complete")
            }
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

    private var speechTitle: String {
        if model.isPlanning || model.runnerStatus == "Planning" { return "sorting inbox" }
        if model.isGenerating || model.runnerStatus == "Generating" { return "building workflow" }
        if model.isRunning || model.runnerStatus == "Running" { return "running locally" }
        if model.lifePlan != nil && !model.hasWorkflow { return "brief ready" }
        if model.approvalRequired { return "needs trust" }
        return "personal assistant"
    }

    private var statusMessage: String {
        if isWaving { return "I'm here. Drop the messy notes and I'll keep the thread together." }
        if model.isPlanning || model.runnerStatus == "Planning" { return "Sorting tasks, links, questions, and the first thing I can automate." }
        if model.isGenerating || model.runnerStatus == "Generating" { return "Building the local workflow now. Scripts stay visible before anything runs." }
        if model.isRunning || model.runnerStatus == "Running" { return "Running the trusted steps. Logs stay local so you can inspect what happened." }
        if model.runnerStatus == "Failed" || model.runnerStatus == "Generation failed" || model.runnerStatus == "Planning failed" { return "That hit a snag. The log below has the exact error." }
        if model.runnerStatus == "Complete" { return "Done. The result and the local run log are both saved here." }
        if let plan = model.lifePlan, !model.hasWorkflow { return "I found \(plan.tasks.count) task(s) and \(plan.automations.count) automation idea(s). Pick one and I'll wire it up." }
        if model.approvalRequired || model.runnerStatus == "Generated" || model.runnerStatus == "Loaded" { return "Review this exact version, then trust it before it touches files or apps." }
        return "Paste the messy context. I'll turn it into a small plan, then a workflow."
    }

    private func currentAnimationRow() -> Int {
        if isWaving { return 3 }
        if model.isPlanning || model.runnerStatus == "Planning" { return 6 }
        if model.isGenerating || model.runnerStatus == "Generating" { return 6 }
        if model.isRunning || model.runnerStatus == "Running" { return 7 }
        if model.runnerStatus == "Failed" || model.runnerStatus == "Generation failed" || model.runnerStatus == "Planning failed" { return 5 }
        if model.runnerStatus == "Complete" { return 4 }
        if model.lifePlan != nil || model.approvalRequired || model.runnerStatus == "Generated" || model.runnerStatus == "Loaded" { return 8 }
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

private struct PetSpeechBubble: View {
    var title: String
    var message: String
    var highlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(StudioPalette.accentBright)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(StudioPalette.text)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioPalette.panelStrong)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(highlighted ? StudioPalette.accentBright.opacity(0.4) : StudioPalette.line, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            SpeechBubbleTail()
                .fill(StudioPalette.panelStrong)
                .frame(width: 11, height: 16)
                .offset(x: 52, y: -10)
        }
    }
}

private struct SpeechBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PetStatusBuddy: View {
    var label: String
    var row: Int
    var col: Int
    var active: Bool

    var body: some View {
        HStack(spacing: 5) {
            NexPetFrameView(col: col, row: row, scale: 0.19)
                .frame(width: 36, height: 38)
                .scaleEffect(active ? 1.0 : 0.92)
                .opacity(active ? 1.0 : 0.52)

            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(active ? StudioPalette.accentBright : StudioPalette.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(height: 42)
        .frame(maxWidth: .infinity)
        .background(active ? StudioPalette.accentSoft : StudioPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(active ? StudioPalette.accent.opacity(0.55) : StudioPalette.line, lineWidth: 1))
    }
}

// MARK: - Button Styles — Geometric / Angular

private struct CanvasTabButtonStyle: ButtonStyle {
    var isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
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
            .font(.system(size: 13, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
            .font(.system(size: 13, weight: .bold))
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
        .font(.system(size: 12, weight: .semibold))
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
