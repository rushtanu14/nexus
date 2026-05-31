import Foundation
import Observation

public enum NodeKind: String, Codable, CaseIterable {
    case trigger = "Trigger"
    case findScreenshots = "Find Screenshots"
    case reviewWarnings = "Review Warnings"
    case moveFiles = "Move Files"
    case logRun = "Log Run"
    case accessibilityFallback = "Accessibility Fallback"
    case automationAction = "Automation Action"
}

public enum NodeStatus: String, Codable {
    case idle = "Idle"
    case ready = "Ready"
    case warning = "Warning"
    case success = "Success"
    case blocked = "Blocked"
}

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var displayString: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .bool(let value): return String(value)
        case .object, .array:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return (try? String(data: encoder.encode(self), encoding: .utf8)) ?? "JSON output"
        case .null: return "null"
        }
    }
}

public struct ExecutableField: Codable, Equatable, Sendable {
    public var id: String
    public var type: String
    public var required: Bool
    public var label: String
    public var value: String

    public init(id: String, type: String, required: Bool, label: String, value: String) {
        self.id = id
        self.type = type
        self.required = required
        self.label = label
        self.value = value
    }
}

public struct ExecutableMeta: Codable, Equatable, Sendable {
    public var app: String
    public var category: String
    public var action: String
    public var label: String
    public var source: String

    public init(app: String, category: String, action: String, label: String, source: String) {
        self.app = app
        self.category = category
        self.action = action
        self.label = label
        self.source = source
    }
}

public struct RunnerStep: Codable, Equatable, Sendable {
    public var primitive: String
    public var args: [String: JSONValue]

    public init(primitive: String, args: [String: JSONValue]) {
        self.primitive = primitive
        self.args = args
    }
}

public struct ExecutableRunner: Codable, Equatable, Sendable {
    public var steps: [RunnerStep]
    public var output_binding: String?

    public init(steps: [RunnerStep], output_binding: String?) {
        self.steps = steps
        self.output_binding = output_binding
    }

    enum CodingKeys: String, CodingKey {
        case steps
        case output_binding
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(steps, forKey: .steps)
        if let output_binding {
            try container.encode(output_binding, forKey: .output_binding)
        } else {
            try container.encodeNil(forKey: .output_binding)
        }
    }
}

public struct MCPReference: Codable, Equatable, Sendable {
    public var server: String
    public var tool: String

    public init(server: String, tool: String) {
        self.server = server
        self.tool = tool
    }
}

public struct ExecutableNode: Codable, Equatable, Sendable {
    public var id: String
    public var meta: ExecutableMeta
    public var fields: [ExecutableField]
    public var runner: ExecutableRunner
    public var mcp: MCPReference?

    public init(id: String, meta: ExecutableMeta, fields: [ExecutableField], runner: ExecutableRunner, mcp: MCPReference?) {
        self.id = id
        self.meta = meta
        self.fields = fields
        self.runner = runner
        self.mcp = mcp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case meta
        case fields
        case runner
        case mcp
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(meta, forKey: .meta)
        try container.encode(fields, forKey: .fields)
        try container.encode(runner, forKey: .runner)
        if let mcp {
            try container.encode(mcp, forKey: .mcp)
        } else {
            try container.encodeNil(forKey: .mcp)
        }
    }
}

public struct EngineRunResult: Codable, Equatable, Sendable {
    public var output: JSONValue?
    public var error: String?
    public var failed_step: Int?

    public init(output: JSONValue?, error: String?, failed_step: Int?) {
        self.output = output
        self.error = error
        self.failed_step = failed_step
    }
}

public protocol WorkflowEngineClientProtocol: Sendable {
    func generateNode(intent: String, context: [String: JSONValue]) async throws -> ExecutableNode
    func runNode(_ node: ExecutableNode, context: [String: JSONValue]) async throws -> EngineRunResult
    func listNodes() async throws -> [ExecutableNode]
}

public struct WorkflowEngineClient: WorkflowEngineClientProtocol, Sendable {
    public var baseURL: URL

    public init(baseURL: URL = URL(string: "http://127.0.0.1:3131")!) {
        self.baseURL = baseURL
    }

    public func generateNode(intent: String, context: [String: JSONValue] = [:]) async throws -> ExecutableNode {
        try await request(path: "/node/generate", body: GenerateRequest(intent: intent, context: context), response: ExecutableNode.self)
    }

    public func runNode(_ node: ExecutableNode, context: [String: JSONValue] = [:]) async throws -> EngineRunResult {
        try await request(path: "/node/run", body: RunRequest(node: node, context: context), response: EngineRunResult.self)
    }

    public func listNodes() async throws -> [ExecutableNode] {
        let (data, urlResponse) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("/node/list"))
        guard let httpResponse = urlResponse as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw EngineClientError.requestFailed(String(data: data, encoding: .utf8) ?? "Request failed")
        }
        return try JSONDecoder().decode([ExecutableNode].self, from: data)
    }

    private func request<Request: Encodable, Response: Decodable>(path: String, body: Request, response: Response.Type) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard let httpResponse = urlResponse as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw EngineClientError.requestFailed(String(data: data, encoding: .utf8) ?? "Request failed")
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            if let payload = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw EngineClientError.requestFailed(payload.error)
            }
            throw error
        }
    }
}

private struct GenerateRequest: Encodable {
    var intent: String
    var context: [String: JSONValue]
}

private struct RunRequest: Encodable {
    var node: ExecutableNode
    var context: [String: JSONValue]
}

private struct ErrorResponse: Decodable {
    var error: String
}

public enum EngineClientError: Error, LocalizedError {
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .requestFailed(let message): return message
        }
    }
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
    public var executableNode: ExecutableNode?
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
    public var executableNode: ExecutableNode?
    public var executionOutput: String?
}

@Observable
public final class StudioModel {
    public var prompt = ""
    public var workflow: GeneratedWorkflow
    public var selectedNodeID: UUID?
    public var pendingConnectionSourceID: UUID?
    public var logs: [RunLog]
    public var runnerStatus = "Idle"
    public var isGenerating = false
    public var isRunning = false
    public var savedNodes: [ExecutableNode] = []
    private let engineClient: any WorkflowEngineClientProtocol

    public init(seed: Bool = false, engineClient: any WorkflowEngineClientProtocol = WorkflowEngineClient()) {
        self.engineClient = engineClient
        self.workflow = StudioModel.emptyWorkflow()
        self.logs = []
        if seed {
            prompt = "Open example.com and extract the page title."
            generateWorkflow()
        }
    }

    public var selectedNode: WorkflowNode? { workflow.nodes.first(where: { $0.id == selectedNodeID }) }
    public var hasWorkflow: Bool { !workflow.nodes.isEmpty }
    public var canGenerate: Bool { !isGenerating && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var approvalRequired: Bool { hasWorkflow && workflow.approvedSignature != signature }
    public var moveImpacts: [ImpactItem] { workflow.impacts.filter { $0.action.lowercased() == "move" } }
    public var signature: String {
        let nodes = workflow.nodes.map { "\($0.id):\($0.x):\($0.y):\($0.executableNode?.id ?? "visual")" }.joined(separator: "|")
        let edges = workflow.edges.map { "\($0.from)>\($0.to)" }.joined(separator: "|")
        return String((workflow.rawScript + nodes + edges).hashValue)
    }

    public func generateWorkflow() {
        Task { await generateWorkflowFromBackend() }
    }

    public func generateWorkflowFromBackend() async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            workflow = StudioModel.emptyWorkflow()
            selectedNodeID = nil
            runnerStatus = "Idle"
            return
        }

        prompt = trimmedPrompt
        isGenerating = true
        runnerStatus = "Generating"
        defer { isGenerating = false }
        do {
            let node = try await engineClient.generateNode(intent: trimmedPrompt, context: [:])
            workflow = StudioModel.workflow(from: node, prompt: trimmedPrompt)
            selectedNodeID = workflow.nodes.first?.id
            pendingConnectionSourceID = nil
            runnerStatus = "Generated"
            log(node: "Local AI", message: "Generated executable workflow with \(node.runner.steps.count) runner step(s)", status: .success)
            await refreshSavedNodes()
        } catch {
            runnerStatus = "Generation failed"
            log(node: "Local AI", message: error.localizedDescription, status: .blocked)
        }
    }

    public func select(_ node: WorkflowNode) { selectedNodeID = node.id }

    public func setNodePosition(id: UUID, x: Double, y: Double) {
        guard let index = workflow.nodes.firstIndex(where: { $0.id == id }) else { return }
        workflow.nodes[index].x = max(x, 24)
        workflow.nodes[index].y = max(y, 82)
        selectedNodeID = id
    }

    public func beginConnection(from id: UUID) {
        guard workflow.nodes.contains(where: { $0.id == id }) else { return }
        pendingConnectionSourceID = id
        selectedNodeID = id
        log(node: "Canvas", message: "Choose another node input to create a visual connection", status: .ready)
    }

    public func completeConnection(to id: UUID, fallback: Bool = false) {
        guard let source = pendingConnectionSourceID, source != id else {
            pendingConnectionSourceID = nil
            return
        }
        pendingConnectionSourceID = nil
        guard !workflow.edges.contains(where: { $0.from == source && $0.to == id }) else { return }
        guard !wouldCreateCycle(from: source, to: id) else {
            log(node: "Canvas", message: "Connection blocked because it would create a cycle", status: .blocked)
            return
        }
        workflow.edges.append(WorkflowEdge(id: UUID(), from: source, to: id, isFallback: fallback))
        selectedNodeID = id
        refreshExecutableSummary()
    }

    public func removeEdge(_ edgeID: UUID) {
        workflow.edges.removeAll(where: { $0.id == edgeID })
        refreshExecutableSummary()
    }

    public func addGeneratedNode(kind: NodeKind) {
        log(node: "Canvas", message: "Canvas-only nodes are disabled for executable workflows", status: .blocked)
    }

    public func dryRun() {
        guard hasWorkflow else { return }
        runnerStatus = "Dry run"
        let stepCount = workflow.nodes.compactMap(\.executableNode).reduce(0) { $0 + $1.runner.steps.count }
        log(node: "Dry Run", message: "Would run \(workflow.nodes.count) canvas node(s) with \(stepCount) deterministic runner step(s)", status: .ready)
    }

    public func refreshSavedNodes() async {
        var lastError: Error?
        for attempt in 0..<8 {
            do {
                savedNodes = try await engineClient.listNodes()
                return
            } catch {
                lastError = error
                if attempt < 7 {
                    try? await Task.sleep(for: .milliseconds(350))
                }
            }
        }
        if let lastError {
            log(node: "Your Nodes", message: lastError.localizedDescription, status: .blocked)
        }
    }

    public func loadSavedNode(_ node: ExecutableNode) {
        if !hasWorkflow {
            workflow = StudioModel.workflow(from: node, prompt: node.meta.label)
            selectedNodeID = workflow.nodes.first?.id
        } else {
            let index = workflow.nodes.count
            let canvasNode = StudioModel.canvasNode(from: node, index: index)
            workflow.nodes.append(canvasNode)
            workflow.warnings = StudioModel.warnings(for: workflow.nodes.compactMap(\.executableNode))
            workflow.impacts = StudioModel.impacts(for: workflow.nodes.compactMap(\.executableNode))
            selectedNodeID = canvasNode.id
            refreshExecutableSummary()
        }
        pendingConnectionSourceID = nil
        runnerStatus = "Loaded"
        log(node: "Your Nodes", message: "Added \(node.meta.label) to the canvas", status: .success)
    }

    public func approveVersion() {
        guard hasWorkflow else { return }
        workflow.approvedSignature = signature
        log(node: "Trust", message: "Trusted this exact executable node", status: .success)
    }

    public func runLocally() {
        Task { await runLocallyWithBackend() }
    }

    public func runLocallyWithBackend() async {
        guard hasWorkflow else { return }
        guard !approvalRequired else {
            runnerStatus = "Blocked"
            log(node: "Trust", message: "Run blocked until this executable version is approved", status: .blocked)
            return
        }

        isRunning = true
        runnerStatus = "Running"
        defer { isRunning = false }
        do {
            let orderedNodes = try executionOrder()
            var priorOutputs: [String: JSONValue] = [:]
            var finalOutput: JSONValue?
            for (index, canvasNode) in orderedNodes.enumerated() {
                guard let executable = canvasNode.executableNode else { continue }
                let context: [String: JSONValue] = ["nodes": .object(priorOutputs)]
                let result = try await engineClient.runNode(executable, context: context)
                if let error = result.error {
                    throw EngineClientError.requestFailed("\(canvasNode.title): \(error)")
                }
                finalOutput = result.output
                priorOutputs[String(index)] = .object(["output": result.output ?? .null])
                if let workflowIndex = workflow.nodes.firstIndex(where: { $0.id == canvasNode.id }) {
                    workflow.nodes[workflowIndex].status = .success
                }
            }
            let output = finalOutput?.displayString ?? "Completed \(orderedNodes.count) canvas node(s)"
            workflow.executionOutput = output
            runnerStatus = "Complete"
            log(node: "Runner", message: output, status: .success)
        } catch {
            runnerStatus = "Failed"
            log(node: "Runner", message: error.localizedDescription, status: .blocked)
        }
    }

    public func undoLastRun() {
        log(node: "Undo", message: "Undo is unavailable for this generated runner", status: .blocked)
    }

    public func requestAccessibility() {
        workflow.accessibilityRequested = true
        log(node: "Permissions", message: "macOS Accessibility prompt opened for app control", status: .warning)
    }

    private func log(node: String, message: String, status: NodeStatus) {
        logs.insert(RunLog(id: UUID(), time: Date(), node: node, message: message, status: status), at: 0)
    }

    private func executionOrder() throws -> [WorkflowNode] {
        var incoming = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, 0) })
        var outgoing: [UUID: [UUID]] = [:]
        for edge in workflow.edges {
            incoming[edge.to, default: 0] += 1
            outgoing[edge.from, default: []].append(edge.to)
        }
        var queue = workflow.nodes.filter { incoming[$0.id] == 0 }
        var ordered: [WorkflowNode] = []
        while !queue.isEmpty {
            let node = queue.removeFirst()
            ordered.append(node)
            for destination in outgoing[node.id, default: []] {
                incoming[destination, default: 0] -= 1
                if incoming[destination] == 0, let next = workflow.nodes.first(where: { $0.id == destination }) {
                    queue.append(next)
                }
            }
        }
        guard ordered.count == workflow.nodes.count else {
            throw EngineClientError.requestFailed("Canvas graph contains a cycle")
        }
        return ordered
    }

    private func wouldCreateCycle(from source: UUID, to destination: UUID) -> Bool {
        var stack = [destination]
        var visited = Set<UUID>()
        while let current = stack.popLast() {
            if current == source { return true }
            guard visited.insert(current).inserted else { continue }
            stack.append(contentsOf: workflow.edges.filter { $0.from == current }.map(\.to))
        }
        return false
    }

    private func refreshExecutableSummary() {
        let executableNodes = workflow.nodes.compactMap(\.executableNode)
        workflow.rawScript = StudioModel.prettyJSON(executableNodes)
        workflow.executableNode = executableNodes.count == 1 ? executableNodes[0] : nil
    }

    public static func emptyWorkflow() -> GeneratedWorkflow {
        GeneratedWorkflow(name: "", prompt: "", nodes: [], edges: [], warnings: [], impacts: [], rawScript: "", approvedSignature: nil, accessibilityRequested: false, lastMovedFiles: [], executableNode: nil, executionOutput: nil)
    }

    public static func workflow(from executableNode: ExecutableNode, prompt: String) -> GeneratedWorkflow {
        let nodes = [canvasNode(from: executableNode, index: 0)]
        return GeneratedWorkflow(
            name: executableNode.meta.label,
            prompt: prompt,
            nodes: nodes,
            edges: [],
            warnings: warnings(for: [executableNode]),
            impacts: impacts(for: [executableNode]),
            rawScript: prettyJSON([executableNode]),
            approvedSignature: nil,
            accessibilityRequested: false,
            lastMovedFiles: [],
            executableNode: executableNode,
            executionOutput: nil
        )
    }

    private static func canvasNode(from executableNode: ExecutableNode, index: Int) -> WorkflowNode {
        WorkflowNode(
            id: UUID(),
            kind: .automationAction,
            title: executableNode.meta.label,
            subtitle: executableNode.runner.steps.map(\.primitive).joined(separator: " -> "),
            x: 84 + Double((index % 5) * 220),
            y: 172 + Double((index / 5) * 164),
            status: .ready,
            parameters: ["Runner steps": executableNode.runner.steps.map(\.primitive).joined(separator: " -> ")],
            executableNode: executableNode
        )
    }

    private static func warnings(for nodes: [ExecutableNode]) -> [String] {
        var warnings: [String] = []
        let primitives = Set(nodes.flatMap { $0.runner.steps.map(\.primitive) })
        if primitives.contains("fs_write") { warnings.append("This workflow can write files on your Mac.") }
        if primitives.contains("shell_run") { warnings.append("This workflow can run a local shell command.") }
        if primitives.contains("http_request") { warnings.append("This workflow can send data to a website.") }
        if primitives.contains("browser_click") || primitives.contains("browser_fill") { warnings.append("This workflow can interact with a browser page.") }
        return warnings.isEmpty ? ["Review the exact runner steps before approving."] : warnings
    }

    private static func impacts(for nodes: [ExecutableNode]) -> [ImpactItem] {
        nodes.flatMap { $0.runner.steps }.map { step in
            ImpactItem(id: UUID(), action: step.primitive, source: step.args.values.map(\.displayString).joined(separator: ", "), destination: "Local runner")
        }
    }

    private static func prettyJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? String(data: encoder.encode(value), encoding: .utf8)) ?? "Unable to render executable node"
    }
}
