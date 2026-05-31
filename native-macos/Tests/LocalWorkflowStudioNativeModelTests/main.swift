import LocalWorkflowStudioCore

@main
struct ModelTestRunner {
    static func main() {
        testGenerateWorkflowCreatesNodeCanvas()
        testDryRunMarksReviewAndWritesLog()
        testApprovalBlocksAndThenAllowsRun()
        testChangingScriptInvalidatesApproval()
        testCanvasEditingInvalidatesApproval()
        testUndoAndAccessibilityPrompt()
        print("LocalWorkflowStudioNativeModelTests passed")
    }

    static func testGenerateWorkflowCreatesNodeCanvas() {
        let model = StudioModel(seed: false)
        model.prompt = "Sort screenshots and check warnings"
        model.generateWorkflow()
        precondition(model.workflow.nodes.count == 6)
        precondition(model.workflow.edges.count == 5)
        precondition(model.workflow.nodes.contains(where: { $0.kind == .trigger }))
        precondition(model.workflow.nodes.contains(where: { $0.kind == .accessibilityFallback }))
        precondition(model.selectedNode != nil)
    }

    static func testDryRunMarksReviewAndWritesLog() {
        let model = StudioModel(seed: false)
        model.generateWorkflow()
        model.dryRun()
        let review = model.workflow.nodes.first(where: { $0.kind == .reviewWarnings })
        precondition(review?.status == .warning)
        precondition(model.logs.contains(where: { $0.node == "Dry Run" }))
        precondition(model.logs.contains(where: { $0.node == "Dry Run" && $0.message.contains("Found 2 screenshots") }))
    }

    static func testApprovalBlocksAndThenAllowsRun() {
        let model = StudioModel(seed: false)
        model.generateWorkflow()
        precondition(model.approvalRequired)
        model.runLocally()
        precondition(model.runnerStatus == "Blocked")
        model.approveVersion()
        precondition(!model.approvalRequired)
        model.runLocally()
        precondition(model.runnerStatus == "Complete")
        precondition(model.workflow.lastMovedFiles.count == 2)
        precondition(model.workflow.lastMovedFiles.allSatisfy { $0.action == "move" })
        precondition(model.logs.contains(where: { $0.node == "Move Files" && $0.message.contains("Moved 2 screenshots") }))
    }

    static func testChangingScriptInvalidatesApproval() {
        let model = StudioModel(seed: false)
        model.generateWorkflow()
        model.approveVersion()
        precondition(!model.approvalRequired)
        model.workflow.rawScript += "\necho changed"
        precondition(model.approvalRequired)
    }

    static func testCanvasEditingInvalidatesApproval() {
        let model = StudioModel(seed: false)
        model.generateWorkflow()
        model.approveVersion()
        precondition(!model.approvalRequired)

        let firstNode = model.workflow.nodes[0]
        model.setNodePosition(id: firstNode.id, x: firstNode.x + 80, y: firstNode.y + 40)
        precondition(model.selectedNode?.id == firstNode.id)
        precondition(model.approvalRequired)

        model.approveVersion()
        precondition(!model.approvalRequired)
        let edgeCount = model.workflow.edges.count
        model.beginConnection(from: model.workflow.nodes[0].id)
        model.completeConnection(to: model.workflow.nodes[2].id)
        precondition(model.workflow.edges.count == edgeCount + 1)
        precondition(model.pendingConnectionSourceID == nil)
        precondition(model.approvalRequired)

        model.approveVersion()
        guard let addedEdge = model.workflow.edges.last else {
            preconditionFailure("Expected an edge to remove")
        }
        model.removeEdge(addedEdge.id)
        precondition(model.workflow.edges.count == edgeCount)
        precondition(model.approvalRequired)

        model.addGeneratedNode(kind: .reviewWarnings)
        precondition(model.workflow.nodes.count == 7)
        precondition(model.selectedNode?.kind == .reviewWarnings)
    }

    static func testUndoAndAccessibilityPrompt() {
        let model = StudioModel(seed: false)
        model.generateWorkflow()
        model.approveVersion()
        model.runLocally()
        model.undoLastRun()
        precondition(model.workflow.lastMovedFiles.isEmpty)
        precondition(model.runnerStatus == "Undone")
        precondition(model.logs.contains(where: { $0.node == "Undo" && $0.message.contains("Restored 2 moved files") }))
        model.requestAccessibility()
        precondition(model.workflow.accessibilityRequested)
        precondition(model.selectedNode?.kind == .accessibilityFallback)
    }
}
