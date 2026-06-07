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

public struct LifePlanStats: Codable, Equatable, Sendable {
    public var tasks: Int
    public var resources: Int
    public var questions: Int
    public var automations: Int

    public init(tasks: Int, resources: Int, questions: Int, automations: Int) {
        self.tasks = tasks
        self.resources = resources
        self.questions = questions
        self.automations = automations
    }
}

public struct LifeTask: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var status: String
    public var dueDateText: String
    public var priority: String
    public var source: String

    public init(id: String, title: String, status: String, dueDateText: String, priority: String, source: String) {
        self.id = id
        self.title = title
        self.status = status
        self.dueDateText = dueDateText
        self.priority = priority
        self.source = source
    }
}

public struct LifeResource: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var url: String
    public var type: String

    public init(id: String, title: String, url: String, type: String) {
        self.id = id
        self.title = title
        self.url = url
        self.type = type
    }
}

public struct LifeQuestion: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

public struct LifeNextMeeting: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var dateText: String
    public var timeText: String
    public var source: String

    public init(id: String, title: String, dateText: String, timeText: String, source: String) {
        self.id = id
        self.title = title
        self.dateText = dateText
        self.timeText = timeText
        self.source = source
    }
}

public struct LifeAutomation: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var intent: String
    public var impact: String
    public var riskLevel: String
    public var requiresApproval: Bool

    public init(id: String, title: String, intent: String, impact: String, riskLevel: String, requiresApproval: Bool) {
        self.id = id
        self.title = title
        self.intent = intent
        self.impact = impact
        self.riskLevel = riskLevel
        self.requiresApproval = requiresApproval
    }
}

public struct LifePlan: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var date: String
    public var context: String
    public var brief: String
    public var sourceText: String
    public var stats: LifePlanStats
    public var tasks: [LifeTask]
    public var resources: [LifeResource]
    public var questions: [LifeQuestion]
    public var nextMeeting: LifeNextMeeting?
    public var automations: [LifeAutomation]
    public var warnings: [String]
    public var rawSummary: String

    public init(
        id: String,
        title: String,
        date: String,
        context: String,
        brief: String,
        sourceText: String,
        stats: LifePlanStats,
        tasks: [LifeTask],
        resources: [LifeResource],
        questions: [LifeQuestion],
        nextMeeting: LifeNextMeeting?,
        automations: [LifeAutomation],
        warnings: [String],
        rawSummary: String
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.context = context
        self.brief = brief
        self.sourceText = sourceText
        self.stats = stats
        self.tasks = tasks
        self.resources = resources
        self.questions = questions
        self.nextMeeting = nextMeeting
        self.automations = automations
        self.warnings = warnings
        self.rawSummary = rawSummary
    }
}

public struct BrainConfig: Codable, Equatable, Sendable {
    public var provider: String
    public var model: String
    public var apiKey: String
    public var baseUrl: String

    public init(provider: String = "ollama", model: String = "qwen2.5-coder:1.5b", apiKey: String = "", baseUrl: String = "") {
        self.provider = provider
        self.model = model
        self.apiKey = apiKey
        self.baseUrl = baseUrl
    }
}

public struct BrainCatalog: Equatable, Sendable {
    public var ollama = ["qwen2.5-coder:1.5b", "qwen2.5-coder:7b", "llama3.2:3b", "gemma3:4b"]
    public var lmstudio = ["qwen2.5-coder-7b-instruct", "llama-3.2-3b-instruct", "gemma-3-4b-it"]

    public init() {}
}

public protocol WorkflowEngineClientProtocol: Sendable {
    func generateNode(intent: String, context: [String: JSONValue]) async throws -> ExecutableNode
    func runNode(_ node: ExecutableNode, context: [String: JSONValue]) async throws -> EngineRunResult
    func listNodes() async throws -> [ExecutableNode]
    func createLifePlan(text: String) async throws -> LifePlan
    func deleteNode(id: String) async throws
    func clearNodes() async throws
    func completeWithNex(prompt: String, brain: BrainConfig) async throws -> String
    func prepareBrain(_ brain: BrainConfig) async throws -> String
}

public extension WorkflowEngineClientProtocol {
    func deleteNode(id: String) async throws {}
    func clearNodes() async throws {}
    func completeWithNex(prompt: String, brain: BrainConfig) async throws -> String {
        throw EngineClientError.requestFailed("Nex completion is unavailable for this engine client")
    }
    func prepareBrain(_ brain: BrainConfig) async throws -> String {
        throw EngineClientError.requestFailed("Brain preparation is unavailable for this engine client")
    }
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

    public func createLifePlan(text: String) async throws -> LifePlan {
        try await request(path: "/life/plan", body: LifePlanRequest(text: text), response: LifePlan.self)
    }

    public func deleteNode(id: String) async throws {
        _ = try await request(path: "/node/delete", body: NodeIDRequest(id: id), response: OKResponse.self)
    }

    public func clearNodes() async throws {
        _ = try await request(path: "/node/clear", body: EmptyRequest(), response: OKResponse.self)
    }

    public func completeWithNex(prompt: String, brain: BrainConfig) async throws -> String {
        try await request(path: "/nex/complete", body: NexCompleteRequest(prompt: prompt, brain: brain), response: NexCompleteResponse.self).completion
    }

    public func prepareBrain(_ brain: BrainConfig) async throws -> String {
        try await request(path: "/brain/prepare", body: BrainRequest(brain: brain), response: BrainPrepareResponse.self).status
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

private struct LifePlanRequest: Encodable {
    var text: String
}

private struct NodeIDRequest: Encodable {
    var id: String
}

private struct EmptyRequest: Encodable {}

private struct OKResponse: Decodable {
    var ok: Bool
}

private struct NexCompleteRequest: Encodable {
    var prompt: String
    var brain: BrainConfig
}

private struct NexCompleteResponse: Decodable {
    var completion: String
}

private struct BrainRequest: Encodable {
    var brain: BrainConfig
}

private struct BrainPrepareResponse: Decodable {
    var status: String
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
    public var deliverable: String = "Complete the configured automation"
    public var schedule: String = "Manual"
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
    public var groupedSchedule: String = ""
}

public struct SavedWorkflow: Identifiable, Codable, Equatable {
    public var id: UUID
    public var workflow: GeneratedWorkflow
    public var savedAt: Date

    public init(id: UUID = UUID(), workflow: GeneratedWorkflow, savedAt: Date = Date()) {
        self.id = id
        self.workflow = workflow
        self.savedAt = savedAt
    }
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
    public var isPlanning = false
    public var lifePlan: LifePlan?
    public var savedNodes: [ExecutableNode] = []
    public var savedWorkflows: [SavedWorkflow] = []
    public var brainConfig = BrainConfig()
    public let brainCatalog = BrainCatalog()
    public var brainStatus = "Ready"
    private let engineClient: any WorkflowEngineClientProtocol
    private var scheduleTimer: Timer?
    private var lastScheduleRuns: [String: Date] = [:]
    private let savedWorkflowsKey = "NexusSavedWorkflows"
    private let brainConfigKey = "NexusBrainConfig"

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
    public var canCreateLifePlan: Bool { !isPlanning && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var topAutomationIntent: String? { lifePlan?.automations.first?.intent }
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

    public func createLifePlan() {
        Task { await createLifePlanFromBackend() }
    }

    public func createLifePlanFromBackend() async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            lifePlan = nil
            runnerStatus = "Idle"
            return
        }

        prompt = trimmedPrompt
        isPlanning = true
        runnerStatus = "Planning"
        defer { isPlanning = false }
        do {
            let plan = try await engineClient.createLifePlan(text: trimmedPrompt)
            lifePlan = plan
            runnerStatus = "Plan ready"
            log(node: "Life AI", message: "Prepared \(plan.tasks.count) task(s), \(plan.questions.count) question(s), and \(plan.automations.count) automation suggestion(s)", status: .success)
        } catch {
            runnerStatus = "Planning failed"
            log(node: "Life AI", message: error.localizedDescription, status: .blocked)
        }
    }

    public func buildWorkflowFromLifePlan() {
        Task { await buildWorkflowFromLifePlanFromBackend() }
    }

    public func buildWorkflowFromLifePlanFromBackend() async {
        guard let automation = lifePlan?.automations.first else {
            log(node: "Life AI", message: "No suggested automation is available yet", status: .blocked)
            return
        }
        await buildWorkflowFromAutomation(automation)
    }

    public func buildWorkflow(from automation: LifeAutomation) {
        Task { await buildWorkflowFromAutomation(automation) }
    }

    public func buildWorkflowFromAutomation(_ automation: LifeAutomation) async {
        prompt = automation.intent
        await generateWorkflowFromBackend()
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

    public func updateSelectedNode(title: String) {
        guard let index = selectedNodeIndex else { return }
        workflow.nodes[index].title = title
    }

    public func updateSelectedNode(deliverable: String) {
        guard let index = selectedNodeIndex else { return }
        workflow.nodes[index].deliverable = deliverable
    }

    public func deleteSelectedCanvasNode() {
        guard let selectedNodeID else { return }
        workflow.nodes.removeAll(where: { $0.id == selectedNodeID })
        workflow.edges.removeAll(where: { $0.from == selectedNodeID || $0.to == selectedNodeID })
        self.selectedNodeID = workflow.nodes.first?.id
        pendingConnectionSourceID = nil
        refreshExecutableSummary()
    }

    public func clearCanvas() {
        workflow = StudioModel.emptyWorkflow()
        selectedNodeID = nil
        pendingConnectionSourceID = nil
        runnerStatus = "Idle"
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

    public func unsaveNode(_ node: ExecutableNode) {
        savedNodes.removeAll(where: { $0.id == node.id })
        Task {
            try? await engineClient.deleteNode(id: node.id)
            await refreshSavedNodes()
        }
    }

    public func unsaveAllNodes() {
        savedNodes = []
        Task {
            try? await engineClient.clearNodes()
            await refreshSavedNodes()
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

    public func refreshSavedWorkflows() async {
        guard let data = UserDefaults.standard.data(forKey: savedWorkflowsKey),
              let decoded = try? JSONDecoder().decode([SavedWorkflow].self, from: data) else {
            savedWorkflows = []
            return
        }
        savedWorkflows = decoded
    }

    public func saveCurrentWorkflow() {
        guard hasWorkflow else { return }
        savedWorkflows.removeAll(where: { $0.workflow.name == workflow.name })
        savedWorkflows.insert(SavedWorkflow(workflow: workflow), at: 0)
        persistSavedWorkflows()
    }

    public func loadWorkflow(_ saved: SavedWorkflow) {
        workflow = saved.workflow
        selectedNodeID = workflow.nodes.first?.id
        pendingConnectionSourceID = nil
        runnerStatus = "Loaded"
    }

    public func deleteWorkflow(_ saved: SavedWorkflow) {
        savedWorkflows.removeAll(where: { $0.id == saved.id })
        persistSavedWorkflows()
    }

    public func setSelectedNodeDaily(_ date: Date) {
        setSelectedNodeSchedule("Every day at \(Self.scheduleTimeFormatter.string(from: date))")
    }

    public func setSelectedNodeRunOnce(_ date: Date) {
        setSelectedNodeSchedule("Once: \(Self.scheduleDateFormatter.string(from: date))")
    }

    public func clearSelectedNodeSchedule() {
        setSelectedNodeSchedule("Manual")
    }

    public func setWorkflowDaily(_ date: Date) {
        workflow.groupedSchedule = "Every day at \(Self.scheduleTimeFormatter.string(from: date))"
    }

    public func setWorkflowRunOnce(_ date: Date) {
        workflow.groupedSchedule = "Once: \(Self.scheduleDateFormatter.string(from: date))"
    }

    public func clearWorkflowSchedule() {
        workflow.groupedSchedule = ""
    }

    public func startScheduleMonitor() {
        guard scheduleTimer == nil else { return }
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.runDueWorkflowIfNeeded()
        }
    }

    public func refreshBrain() async {
        guard let data = UserDefaults.standard.data(forKey: brainConfigKey),
              let decoded = try? JSONDecoder().decode(BrainConfig.self, from: data) else {
            brainStatus = "Ready"
            return
        }
        brainConfig = decoded
        brainStatus = "Loaded"
    }

    public func selectBrainProvider(_ provider: String) {
        brainConfig.provider = provider
        brainConfig.baseUrl = ""
        brainConfig.apiKey = ""
        if provider == "ollama", !brainCatalog.ollama.contains(brainConfig.model) {
            brainConfig.model = brainCatalog.ollama[0]
        } else if provider == "lmstudio", !brainCatalog.lmstudio.contains(brainConfig.model) {
            brainConfig.model = brainCatalog.lmstudio[0]
        }
    }

    public func selectBrainModel(_ model: String) {
        brainConfig.model = model
    }

    public func saveBrain() {
        if let data = try? JSONEncoder().encode(brainConfig) {
            UserDefaults.standard.set(data, forKey: brainConfigKey)
            brainStatus = "Saved"
        }
    }

    public func prepareSelectedBrain() {
        saveBrain()
        brainStatus = "Preparing..."
        Task {
            do {
                brainStatus = try await engineClient.prepareBrain(brainConfig)
            } catch {
                brainStatus = error.localizedDescription
            }
        }
    }

    public func completeWithNex(_ prompt: String) async throws -> String {
        try await engineClient.completeWithNex(prompt: prompt, brain: brainConfig)
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

    private var selectedNodeIndex: Int? {
        guard let selectedNodeID else { return nil }
        return workflow.nodes.firstIndex(where: { $0.id == selectedNodeID })
    }

    private func setSelectedNodeSchedule(_ schedule: String) {
        guard let index = selectedNodeIndex else { return }
        workflow.nodes[index].schedule = schedule
    }

    private func persistSavedWorkflows() {
        if let data = try? JSONEncoder().encode(savedWorkflows) {
            UserDefaults.standard.set(data, forKey: savedWorkflowsKey)
        }
    }

    private func runDueWorkflowIfNeeded() {
        guard hasWorkflow, !approvalRequired, !isRunning else { return }
        let now = Date()
        let groupedDue = isScheduleDue(workflow.groupedSchedule, key: "workflow", now: now)
        let dueNodeIDs = workflow.nodes.filter { isScheduleDue($0.schedule, key: $0.id.uuidString, now: now) }.map(\.id)
        guard groupedDue || !dueNodeIDs.isEmpty else { return }
        if workflow.groupedSchedule.hasPrefix("Once: ") { workflow.groupedSchedule = "" }
        for id in dueNodeIDs where workflow.nodes.first(where: { $0.id == id })?.schedule.hasPrefix("Once: ") == true {
            workflow.nodes[workflow.nodes.firstIndex(where: { $0.id == id })!].schedule = "Manual"
        }
        runLocally()
    }

    private func isScheduleDue(_ schedule: String, key: String, now: Date) -> Bool {
        if schedule.hasPrefix("Once: "),
           let due = Self.scheduleDateFormatter.date(from: String(schedule.dropFirst("Once: ".count))),
           due <= now {
            return true
        }
        guard schedule.hasPrefix("Every day at "),
              let target = Self.scheduleTimeFormatter.date(from: String(schedule.dropFirst("Every day at ".count))) else {
            return false
        }
        let calendar = Calendar.current
        let targetParts = calendar.dateComponents([.hour, .minute], from: target)
        let nowParts = calendar.dateComponents([.hour, .minute], from: now)
        guard targetParts.hour == nowParts.hour, targetParts.minute == nowParts.minute else { return false }
        if let last = lastScheduleRuns[key], calendar.isDate(last, inSameDayAs: now) { return false }
        lastScheduleRuns[key] = now
        return true
    }

    private static let scheduleTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private static let scheduleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

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
