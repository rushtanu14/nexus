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
        }
        .foregroundStyle(StudioPalette.text)
    }

    private func shell(compact: Bool) -> some View {
        ZStack {
            StudioPalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                TitleBar(model: model) {
                    walkthroughStepIndex = 0
                    walkthroughOpen = true
                }
                Divider().overlay(StudioPalette.line)
                HStack(spacing: 0) {
                    Sidebar(model: model, compact: compact)
                    Divider().overlay(StudioPalette.line)
                    PromptPanel(model: model, compact: compact)
                    Divider().overlay(StudioPalette.line)
                    CanvasPanel(model: model, compact: compact)
                    Divider().overlay(StudioPalette.line)
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
        HStack(spacing: 12) {
            Text("Nexus")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            StatusPill(label: "Runner", value: model.runnerStatus, color: StudioPalette.green)
            StatusPill(label: "Permissions", value: model.workflow.accessibilityRequested ? "Requested" : "Local", color: model.workflow.accessibilityRequested ? StudioPalette.amber : StudioPalette.green)
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
        .frame(height: 52)
        .background(StudioPalette.chrome)
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
            Color.black.opacity(0.48).ignoresSafeArea()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("Nexus walkthrough", systemImage: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(StudioPalette.greenBright)
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
                                    .fill(StudioPalette.greenBright)
                                    .frame(width: proxy.size.width * progress)
                            }
                        }
                        .frame(height: 7)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(StudioPalette.greenSoft)
                            Image(systemName: activeStep.icon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(StudioPalette.greenBright)
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
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.line))

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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(StudioPalette.line))
            .shadow(color: .black.opacity(0.44), radius: 40, x: 0, y: 24)
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
                    .background(active ? StudioPalette.greenBright : StudioPalette.panelStrong)
                    .foregroundStyle(active ? Color.black.opacity(0.74) : StudioPalette.muted)
                    .clipShape(Circle())

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
            .background(active ? StudioPalette.greenSoft : StudioPalette.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? StudioPalette.green.opacity(0.8) : StudioPalette.line))
        }
        .buttonStyle(.plain)
    }
}

private struct Sidebar: View {
    @Bindable var model: StudioModel
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 18) {
            VStack(spacing: 10) {
                AppIconImage()
                    .frame(width: compact ? 44 : 78, height: compact ? 44 : 78)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 18, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 12)
                if !compact {
                    Text("Nexus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("v0.1.0 native")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(StudioPalette.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, compact ? 2 : 10)

            SidebarButton(icon: "point.3.connected.trianglepath.dotted", label: "Workflows", active: true, compact: compact)
            SidebarButton(icon: "folder", label: "Files", active: false, compact: compact)
            SidebarButton(icon: "clock", label: "Runs", active: false, compact: compact)
            SidebarButton(icon: "gearshape", label: "Settings", active: false, compact: compact)

            Spacer()

            if compact {
                Image(systemName: "circle.fill")
                    .foregroundStyle(StudioPalette.green)
                    .frame(maxWidth: .infinity)
                    .help("Runner Local")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Runner Local", systemImage: "circle.fill")
                        .foregroundStyle(StudioPalette.green)
                    Text("Workspace")
                        .foregroundStyle(StudioPalette.muted)
                    Text("~/Workflow Studio")
                        .foregroundStyle(StudioPalette.green)
                        .font(.system(.caption, design: .monospaced))
                }
                .font(.system(size: 12, weight: .medium))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StudioPalette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.line))
            }
        }
        .padding(compact ? 10 : 16)
        .frame(width: compact ? 72 : 212)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(4)
        .background(StudioPalette.sidebar)
    }
}

private struct SidebarButton: View {
    var icon: String
    var label: String
    var active: Bool
    var compact: Bool

    var body: some View {
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
        .background(active ? StudioPalette.greenSoft : Color.clear)
        .foregroundStyle(active ? StudioPalette.greenBright : StudioPalette.text)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? StudioPalette.green.opacity(0.85) : .clear))
        .help(label)
    }
}

private struct PromptPanel: View {
    @Bindable var model: StudioModel
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ask AI to build a workflow")
                    .font(.system(size: 16, weight: .semibold))
                Text("Describe it. The app generates the canvas.")
                    .font(.system(size: 12))
                    .foregroundStyle(StudioPalette.muted)
            }

            VStack(alignment: .leading, spacing: 10) {
                Bubble(text: model.prompt, sender: "You", alignRight: true)
                Bubble(text: "I'll build the workflow as nodes, add warnings, and show a dry run before anything runs locally.", sender: "AI", alignRight: false)
            }

            TextEditor(text: $model.prompt)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 118)
                .background(StudioPalette.panelStrong)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.line))

            HStack {
                Button(action: model.generateWorkflow) {
                    Label("Generate canvas", systemImage: "wand.and.sparkles")
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(action: model.dryRun) {
                    Label("Dry run", systemImage: "play")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            HStack(spacing: 8) {
                Button {
                    model.addGeneratedNode(kind: .reviewWarnings)
                } label: {
                    Label("Add warning", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    model.addGeneratedNode(kind: .accessibilityFallback)
                } label: {
                    Label("Add app control", systemImage: "cursorarrow.click.2")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Text("AI-generated automations")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StudioPalette.muted)
                .padding(.top, 4)

            AutomationRow(title: model.workflow.name, subtitle: "Generated from your prompt", active: true)
            AutomationRow(title: "Downloads Sorter", subtitle: "Sort PDFs and image assets", active: false)
            AutomationRow(title: "Browser Research Flow", subtitle: "Record, replay, approve", active: false)

            Spacer()
        }
        .padding(.horizontal, compact ? 14 : 20)
        .padding(.vertical, 18)
        .frame(width: compact ? 292 : 336)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(3)
        .background(StudioPalette.background)
    }
}

private struct CanvasPanel: View {
    @Bindable var model: StudioModel
    var compact: Bool
    @State private var dragOrigins: [UUID: CGPoint] = [:]

    var body: some View {
        let scale: CGFloat = compact ? 0.66 : 1

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("", selection: .constant("Canvas")) {
                    Text("Canvas").tag("Canvas")
                    Text("Code").tag("Code")
                    Text("Runs").tag("Runs")
                }
                .pickerStyle(.segmented)
                .frame(width: compact ? 184 : 220)
                Spacer()
                Text(model.pendingConnectionSourceID == nil ? "Drag nodes. Connect output dots to input dots." : "Choose an input dot to finish the connection.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.pendingConnectionSourceID == nil ? StudioPalette.muted : StudioPalette.greenBright)
                    .lineLimit(1)
                StatusPill(label: "Zoom", value: compact ? "66%" : "100%", color: StudioPalette.muted)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    GridBackground()

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
                            Circle().fill(StudioPalette.green.opacity(0.16))
                            Circle().stroke(StudioPalette.greenBright, lineWidth: 2)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(StudioPalette.greenBright)
                        }
                        .frame(width: 42 * scale, height: 42 * scale)
                        .position(x: nodeCenter(source, scale: scale).x + 94 * scale, y: nodeCenter(source, scale: scale).y)
                    }

                    MiniMap(nodes: model.workflow.nodes, edges: model.workflow.edges)
                        .position(x: 108, y: proxy.size.height - 84)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(Rectangle())
            }
        }
        .frame(minWidth: compact ? 500 : 650)
        .layoutPriority(10)
        .background(StudioPalette.canvas)
    }

    private func nodeCenter(_ node: WorkflowNode, scale: CGFloat) -> CGPoint {
        CGPoint(x: (node.x + 68) * scale, y: (node.y + 52) * scale)
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

private struct InspectorPanel: View {
    @Bindable var model: StudioModel
    var compact: Bool
    var requestAccessibility: () -> Void

    var body: some View {
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
                        .clipShape(Capsule())
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

                        InspectorSection(title: "Affected Files") {
                            VStack(spacing: 8) {
                                ForEach(model.workflow.impacts) { item in
                                    ImpactRow(item: item)
                                }
                            }
                        }

                        InspectorSection(title: "Raw Script") {
                            Text(model.workflow.rawScript)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(StudioPalette.code)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(StudioPalette.codeBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }

                Divider().overlay(StudioPalette.line)

                VStack(spacing: 10) {
                    Button(action: model.approveVersion) {
                        Label(model.approvalRequired ? "Trust this version" : "Trusted version", systemImage: model.approvalRequired ? "touchid" : "checkmark.shield")
                    }
                    .buttonStyle(TrustButtonStyle(disabledLook: !model.approvalRequired))

                    if compact {
                        Button("Dry Run", action: model.dryRun).buttonStyle(SecondaryButtonStyle())
                        Button("Run Locally", action: model.runLocally).buttonStyle(PrimaryButtonStyle())
                        Button("Undo", action: model.undoLastRun).buttonStyle(SecondaryButtonStyle())
                        Button("Request Accessibility", action: requestAccessibility).buttonStyle(SecondaryButtonStyle())
                    } else {
                        HStack(spacing: 8) {
                            Button("Dry Run", action: model.dryRun).buttonStyle(SecondaryButtonStyle())
                            Button("Run Locally", action: model.runLocally).buttonStyle(PrimaryButtonStyle())
                        }

                        HStack(spacing: 8) {
                            Button("Undo", action: model.undoLastRun).buttonStyle(SecondaryButtonStyle())
                            Button("Request Accessibility", action: requestAccessibility).buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
        .frame(width: compact ? 300 : 372)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(4)
        .background(StudioPalette.inspector)
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
        }
    }
}

private struct LogDrawer: View {
    @Bindable var model: StudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Local Run Logs")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Stored locally")
                    .foregroundStyle(StudioPalette.muted)
                    .font(.system(size: 11, weight: .medium))
            }
            ScrollView {
                VStack(spacing: 6) {
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
                        .font(.system(.caption, design: .monospaced))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 132)
        .background(StudioPalette.chrome)
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
                Circle()
                    .fill(statusColor(node.status))
                    .frame(width: 16, height: 16)
                    .overlay(Image(systemName: node.status == .warning ? "exclamationmark" : "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.black.opacity(0.7)))
            }
            .padding(12)
            .frame(width: 136, height: 104)
            .background(node.status == .warning ? StudioPalette.amberSoft : StudioPalette.node)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isConnectionSource ? StudioPalette.greenBright : isSelected ? StudioPalette.greenBright : statusColor(node.status).opacity(0.7), lineWidth: (isSelected || isConnectionSource) ? 2 : 1))
            .shadow(color: .black.opacity(isSelected ? 0.25 : 0.12), radius: isSelected ? 14 : 8, x: 0, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onTapGesture(perform: onSelect)

            ConnectorButton(systemName: "arrow.right", color: StudioPalette.greenBright, action: onStartConnection)
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
                Circle().fill(StudioPalette.canvas)
                Circle().stroke(color.opacity(0.9), lineWidth: 1.5)
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
        .stroke(isFallback ? StudioPalette.amber : StudioPalette.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: isFallback ? [5, 5] : []))
    }
}

private struct EdgeDeleteButton: View {
    var isFallback: Bool
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(StudioPalette.canvas.opacity(0.96))
                Circle().stroke(isFallback ? StudioPalette.amber : StudioPalette.greenBright, lineWidth: isHovering ? 2 : 1.4)
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

private struct GridBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 18
            var path = Path()
            var x: CGFloat = 0
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(StudioPalette.grid), lineWidth: 0.35)
        }
    }
}

private struct MiniMap: View {
    var nodes: [WorkflowNode]
    var edges: [WorkflowEdge]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.16))
            RoundedRectangle(cornerRadius: 6).stroke(StudioPalette.line)
            ForEach(nodes) { node in
                RoundedRectangle(cornerRadius: 2)
                    .fill(statusColor(node.status))
                    .frame(width: 16, height: 10)
                    .position(x: node.x / 8 + 14, y: node.y / 8 + 14)
            }
        }
        .frame(width: 138, height: 74)
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.line))
    }
}

private struct AutomationRow: View {
    var title: String
    var subtitle: String
    var active: Bool

    var body: some View {
        HStack {
            Circle().fill(active ? StudioPalette.green : StudioPalette.muted).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(StudioPalette.muted)
            }
            Spacer()
        }
        .padding(10)
        .background(active ? StudioPalette.greenSoft : StudioPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? StudioPalette.green.opacity(0.65) : StudioPalette.line))
    }
}

private struct InspectorSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
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
                .foregroundStyle(edge.isFallback ? StudioPalette.amber : StudioPalette.greenBright)
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.line))
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ImpactRow: View {
    var item: ImpactItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.action.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(StudioPalette.greenBright)
            Text(item.source)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(item.destination)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(StudioPalette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AppIconImage: View {
    var body: some View {
        if let image = AppAssets.icon {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 18).fill(StudioPalette.greenSoft)
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

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(StudioPalette.greenButton.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(StudioPalette.panel.opacity(configuration.isPressed ? 0.72 : 1))
            .foregroundStyle(StudioPalette.text)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.line))
    }
}

private struct TrustButtonStyle: ButtonStyle {
    var disabledLook: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(disabledLook ? StudioPalette.greenSoft.opacity(0.45) : StudioPalette.greenSoft)
            .foregroundStyle(StudioPalette.greenBright)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.green.opacity(0.7)))
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 34, height: 30)
            .background(StudioPalette.panel.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.line))
    }
}

private struct StatusPill: View {
    var label: String
    var value: String
    var color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label + ":")
                .foregroundStyle(StudioPalette.muted)
            Text(value)
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(StudioPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.line))
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
    }
}

private func statusColor(_ status: NodeStatus) -> Color {
    switch status {
    case .idle: return StudioPalette.muted
    case .ready: return StudioPalette.green
    case .warning: return StudioPalette.amber
    case .success: return StudioPalette.greenBright
    case .blocked: return StudioPalette.red
    }
}

enum StudioPalette {
    static let background = Color(red: 0.055, green: 0.074, blue: 0.071)
    static let chrome = Color(red: 0.075, green: 0.094, blue: 0.09)
    static let sidebar = Color(red: 0.052, green: 0.071, blue: 0.069)
    static let canvas = Color(red: 0.065, green: 0.078, blue: 0.074)
    static let inspector = Color(red: 0.083, green: 0.097, blue: 0.091)
    static let panel = Color.white.opacity(0.055)
    static let panelStrong = Color.white.opacity(0.08)
    static let node = Color(red: 0.12, green: 0.15, blue: 0.14)
    static let userBubble = Color(red: 0.14, green: 0.17, blue: 0.16)
    static let text = Color(red: 0.91, green: 0.93, blue: 0.89)
    static let muted = Color(red: 0.63, green: 0.67, blue: 0.63)
    static let line = Color.white.opacity(0.13)
    static let grid = Color.white.opacity(0.07)
    static let green = Color(red: 0.45, green: 0.74, blue: 0.39)
    static let greenBright = Color(red: 0.58, green: 0.86, blue: 0.49)
    static let greenSoft = Color(red: 0.24, green: 0.40, blue: 0.24).opacity(0.42)
    static let greenButton = Color(red: 0.34, green: 0.52, blue: 0.29)
    static let amber = Color(red: 0.93, green: 0.63, blue: 0.25)
    static let amberSoft = Color(red: 0.35, green: 0.25, blue: 0.12)
    static let red = Color(red: 0.92, green: 0.36, blue: 0.31)
    static let code = Color(red: 0.75, green: 0.91, blue: 0.68)
    static let codeBackground = Color.black.opacity(0.25)
}
