import Foundation
import Observation

public enum NodeKind: String, Codable, CaseIterable {
    case trigger = "Trigger"
    case findScreenshots = "Find Screenshots"
    case reviewWarnings = "Review Warnings"
    case moveFiles = "Move Files"
    case logRun = "Log Run"
    case accessibilityFallback = "Accessibility Fallback"
}

public enum NodeStatus: String, Codable {
    case idle = "Idle"
    case ready = "Ready"
    case warning = "Warning"
    case success = "Success"
    case blocked = "Blocked"
}

public struct WorkflowNode: Identifiable, Codable, Equatable {
    public let id: UUID
    public var kind: NodeKind
    public var title: String
    public var subtitle: String
    public var x: Double
    public var y: Double
    public var status: NodeStatus
    public var parameters: [String: String]
}

public struct WorkflowEdge: Identifiable, Codable, Equatable {
    public let id: UUID
    public var from: UUID
    public var to: UUID
    public var isFallback: Bool
}

public struct ImpactItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var action: String
    public var source: String
    public var destination: String
}

public struct RunLog: Identifiable, Codable, Equatable {
    public let id: UUID
    public var time: Date
    public var node: String
    public var message: String
    public var status: NodeStatus
}

public struct GeneratedWorkflow: Codable, Equatable {
    public var name: String
    public var prompt: String
    public var nodes: [WorkflowNode]
    public var edges: [WorkflowEdge]
    public var warnings: [String]
    public var impacts: [ImpactItem]
    public var rawScript: String
    public var approvedSignature: String?
    public var accessibilityRequested: Bool
    public var lastMovedFiles: [ImpactItem]
}

@Observable
public final class StudioModel {
    public var prompt = "When I take screenshots, find them on my Mac, check for warning indicators, move them to the right folder, and log what happened."
    public var workflow: GeneratedWorkflow
    public var selectedNodeID: UUID?
    public var pendingConnectionSourceID: UUID?
    public var logs: [RunLog]
    public var runnerStatus = "Idle"

    public init(seed: Bool = true) {
        let initialWorkflow = StudioModel.makeWorkflow(prompt: "")
        self.workflow = initialWorkflow
        self.selectedNodeID = initialWorkflow.nodes.first(where: { $0.kind == .reviewWarnings })?.id
        self.logs = []
        if seed {
            generateWorkflow()
        }
    }

    public var selectedNode: WorkflowNode? {
        workflow.nodes.first(where: { $0.id == selectedNodeID }) ?? workflow.nodes.first
    }

    public var approvalRequired: Bool {
        workflow.approvedSignature != signature
    }

    public var signature: String {
        let nodeBits = workflow.nodes.map { node in
            "\(node.id.uuidString):\(node.kind.rawValue):\(node.title):\(Int(node.x)):\(Int(node.y)):\(node.parameters.sorted(by: { $0.key < $1.key }))"
        }
        .joined(separator: "|")
        let edgeBits = workflow.edges.map { edge in
            "\(edge.from.uuidString)>\(edge.to.uuidString):\(edge.isFallback)"
        }
        .joined(separator: "|")
        let signed = workflow.rawScript + nodeBits + edgeBits + workflow.warnings.joined(separator: "|")
        return String(signed.hashValue)
    }

    public func generateWorkflow() {
        workflow = StudioModel.makeWorkflow(prompt: prompt)
        selectedNodeID = workflow.nodes.first(where: { $0.kind == .reviewWarnings })?.id
        pendingConnectionSourceID = nil
        runnerStatus = "Generated"
        logs.insert(RunLog(id: UUID(), time: Date(), node: "AI", message: "Generated workflow canvas from prompt", status: .success), at: 0)
    }

    public func select(_ node: WorkflowNode) {
        selectedNodeID = node.id
    }

    public func setNodePosition(id: UUID, x: Double, y: Double) {
        guard let index = workflow.nodes.firstIndex(where: { $0.id == id }) else { return }
        workflow.nodes[index].x = min(max(x, 24), 1040)
        workflow.nodes[index].y = min(max(y, 82), 560)
        selectedNodeID = id
    }

    public func beginConnection(from id: UUID) {
        guard workflow.nodes.contains(where: { $0.id == id }) else { return }
        pendingConnectionSourceID = id
        selectedNodeID = id
        logs.insert(RunLog(id: UUID(), time: Date(), node: "Canvas", message: "Choose another node input to create a connection", status: .ready), at: 0)
    }

    public func completeConnection(to id: UUID, fallback: Bool = false) {
        guard let source = pendingConnectionSourceID else {
            selectedNodeID = id
            logs.insert(RunLog(id: UUID(), time: Date(), node: "Canvas", message: "Pick an output dot first, then an input dot", status: .blocked), at: 0)
            return
        }
        pendingConnectionSourceID = nil
        guard source != id else {
            selectedNodeID = id
            logs.insert(RunLog(id: UUID(), time: Date(), node: "Canvas", message: "A node cannot connect to itself", status: .blocked), at: 0)
            return
        }
        guard workflow.nodes.contains(where: { $0.id == source }),
              workflow.nodes.contains(where: { $0.id == id }) else {
            return
        }
        guard !workflow.edges.contains(where: { $0.from == source && $0.to == id }) else {
            selectedNodeID = id
            logs.insert(RunLog(id: UUID(), time: Date(), node: "Canvas", message: "That connection already exists", status: .blocked), at: 0)
            return
        }

        workflow.edges.append(WorkflowEdge(id: UUID(), from: source, to: id, isFallback: fallback))
        selectedNodeID = id
        let fromTitle = workflow.nodes.first(where: { $0.id == source })?.title ?? "Node"
        let toTitle = workflow.nodes.first(where: { $0.id == id })?.title ?? "Node"
        logs.insert(RunLog(id: UUID(), time: Date(), node: "Canvas", message: "Connected \(fromTitle) to \(toTitle)", status: .success), at: 0)
    }

    public func removeEdge(_ edgeID: UUID) {
        guard let edge = workflow.edges.first(where: { $0.id == edgeID }) else { return }
        workflow.edges.removeAll(where: { $0.id == edgeID })
        let fromTitle = workflow.nodes.first(where: { $0.id == edge.from })?.title ?? "Node"
        let toTitle = workflow.nodes.first(where: { $0.id == edge.to })?.title ?? "Node"
        logs.insert(RunLog(id: UUID(), time: Date(), node: "Canvas", message: "Removed \(fromTitle) to \(toTitle)", status: .warning), at: 0)
    }

    public func addGeneratedNode(kind: NodeKind) {
        let nextIndex = workflow.nodes.count
        let node = StudioModel.makeNode(kind: kind, x: 160 + Double((nextIndex % 4) * 176), y: 430 + Double((nextIndex / 4) * 128))
        workflow.nodes.append(node)
        selectedNodeID = node.id
        pendingConnectionSourceID = nil
        logs.insert(RunLog(id: UUID(), time: Date(), node: "AI", message: "Added \(node.title) node to the canvas", status: .success), at: 0)
    }

    public func dryRun() {
        runnerStatus = "Dry run"
        logs.insert(RunLog(id: UUID(), time: Date(), node: "Dry Run", message: "Found \(workflow.impacts.count) screenshots that would move", status: .ready), at: 0)
        mark(.findScreenshots, as: .success)
        mark(.reviewWarnings, as: .warning)
    }

    public func approveVersion() {
        workflow.approvedSignature = signature
        logs.insert(RunLog(id: UUID(), time: Date(), node: "Trust", message: "Trusted this exact workflow version", status: .success), at: 0)
    }

    public func runLocally() {
        guard !approvalRequired else {
            logs.insert(RunLog(id: UUID(), time: Date(), node: "Trust", message: "Run blocked until this version is approved", status: .blocked), at: 0)
            runnerStatus = "Blocked"
            return
        }

        workflow.lastMovedFiles = workflow.impacts
        runnerStatus = "Complete"
        mark(.moveFiles, as: .success)
        mark(.logRun, as: .success)
        logs.insert(RunLog(id: UUID(), time: Date(), node: "Move Files", message: "Moved \(workflow.impacts.count) screenshots to ~/Pictures/Workflow Studio", status: .success), at: 0)
        logs.insert(RunLog(id: UUID(), time: Date(), node: "Workflow", message: "Completed locally", status: .success), at: 0)
    }

    public func undoLastRun() {
        guard !workflow.lastMovedFiles.isEmpty else {
            logs.insert(RunLog(id: UUID(), time: Date(), node: "Undo", message: "No reversible run is available", status: .blocked), at: 0)
            return
        }
        let count = workflow.lastMovedFiles.count
        workflow.lastMovedFiles = []
        runnerStatus = "Undone"
        logs.insert(RunLog(id: UUID(), time: Date(), node: "Undo", message: "Restored \(count) moved files", status: .success), at: 0)
    }

    public func requestAccessibility() {
        workflow.accessibilityRequested = true
        mark(.accessibilityFallback, as: .warning)
        selectedNodeID = workflow.nodes.first(where: { $0.kind == .accessibilityFallback })?.id
        logs.insert(RunLog(id: UUID(), time: Date(), node: "Permissions", message: "Accessibility permission requested only when needed", status: .warning), at: 0)
    }

    private func mark(_ kind: NodeKind, as status: NodeStatus) {
        guard let index = workflow.nodes.firstIndex(where: { $0.kind == kind }) else { return }
        workflow.nodes[index].status = status
    }

    private static func makeNode(kind: NodeKind, x: Double, y: Double) -> WorkflowNode {
        switch kind {
        case .trigger:
            return WorkflowNode(id: UUID(), kind: kind, title: "Trigger", subtitle: "Start condition", x: x, y: y, status: .ready, parameters: ["Mode": "Manual or watcher", "Scope": "User selected"])
        case .findScreenshots:
            return WorkflowNode(id: UUID(), kind: kind, title: "Find Files", subtitle: "Match local files", x: x, y: y, status: .ready, parameters: ["Pattern": "User generated", "Limit": "20"])
        case .reviewWarnings:
            return WorkflowNode(id: UUID(), kind: kind, title: "Review Warnings", subtitle: "Human-readable risk check", x: x, y: y, status: .warning, parameters: ["Warn about": "Files, apps, clicks", "Approval": "Required"])
        case .moveFiles:
            return WorkflowNode(id: UUID(), kind: kind, title: "Move Files", subtitle: "Local file action", x: x, y: y, status: .ready, parameters: ["Destination": "Choose folder", "Undo": "Available"])
        case .logRun:
            return WorkflowNode(id: UUID(), kind: kind, title: "Log Run", subtitle: "Write local history", x: x, y: y, status: .ready, parameters: ["Retention": "14 days", "Privacy": "Local only"])
        case .accessibilityFallback:
            return WorkflowNode(id: UUID(), kind: kind, title: "App Control", subtitle: "Ask for macOS permission", x: x, y: y, status: .idle, parameters: ["Permission": "Ask only if needed", "Stop Hotkey": "Control + Escape"])
        }
    }

    public static func makeWorkflow(prompt: String) -> GeneratedWorkflow {
        let trigger = WorkflowNode(id: UUID(), kind: .trigger, title: "Trigger", subtitle: "Screenshot folder watcher", x: 44, y: 162, status: .ready, parameters: ["Mode": "Folder Watcher", "Scope": "~/Desktop"])
        let find = WorkflowNode(id: UUID(), kind: .findScreenshots, title: "Find Screenshots", subtitle: "Match recent image files", x: 208, y: 162, status: .ready, parameters: ["Pattern": "Screenshot*.png, Screen Shot*.png", "Limit": "20"])
        let review = WorkflowNode(id: UUID(), kind: .reviewWarnings, title: "Review Warnings", subtitle: "On-device visual check", x: 372, y: 162, status: .warning, parameters: ["Vision": "On-device", "Detect": "warnings, alert dialogs, security prompts"])
        let move = WorkflowNode(id: UUID(), kind: .moveFiles, title: "Move Files", subtitle: "Organize by result", x: 536, y: 162, status: .ready, parameters: ["Destination": "~/Pictures/Workflow Studio", "Undo": "Available"])
        let log = WorkflowNode(id: UUID(), kind: .logRun, title: "Log Run", subtitle: "Append local run details", x: 700, y: 162, status: .ready, parameters: ["Retention": "14 days", "Privacy": "Local only"])
        let fallback = WorkflowNode(id: UUID(), kind: .accessibilityFallback, title: "Accessibility Fallback", subtitle: "Ask only if needed", x: 372, y: 346, status: .idle, parameters: ["Permission": "Not requested", "Stop Hotkey": "Control + Escape"])

        return GeneratedWorkflow(
            name: "Screenshot Warning Sorter",
            prompt: prompt,
            nodes: [trigger, find, review, move, log, fallback],
            edges: [
                WorkflowEdge(id: UUID(), from: trigger.id, to: find.id, isFallback: false),
                WorkflowEdge(id: UUID(), from: find.id, to: review.id, isFallback: false),
                WorkflowEdge(id: UUID(), from: review.id, to: move.id, isFallback: false),
                WorkflowEdge(id: UUID(), from: move.id, to: log.id, isFallback: false),
                WorkflowEdge(id: UUID(), from: review.id, to: fallback.id, isFallback: true)
            ],
            warnings: [
                "This workflow can move files on your Mac.",
                "This workflow uses on-device visual checks for warning indicators.",
                "Accessibility control is only requested if the app needs to click or type."
            ],
            impacts: [
                ImpactItem(id: UUID(), action: "move", source: "~/Desktop/Screen Shot 2026-05-30 at 9.14.12 AM.png", destination: "~/Pictures/Workflow Studio/Warnings/"),
                ImpactItem(id: UUID(), action: "move", source: "~/Desktop/Screen Shot 2026-05-30 at 9.18.42 AM.png", destination: "~/Pictures/Workflow Studio/Clean/"),
                ImpactItem(id: UUID(), action: "log", source: "Run summary", destination: "~/Library/Logs/Nexus/")
            ],
            rawScript: """
            mkdir -p "$HOME/Pictures/Workflow Studio"
            find "$HOME/Desktop" -maxdepth 1 -type f \\( -iname "Screenshot*.png" -o -iname "Screen Shot*.png" \\)
            # Move files only after dry run and trust approval.
            """,
            approvedSignature: nil,
            accessibilityRequested: false,
            lastMovedFiles: []
        )
    }
}
