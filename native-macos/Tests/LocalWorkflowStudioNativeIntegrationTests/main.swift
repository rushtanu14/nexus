import Foundation
import LocalWorkflowStudioCore

@main
@MainActor
struct IntegrationTestRunner {
    static func main() async throws {
        let path = "/tmp/nexus-native-live-proof.txt"
        try? FileManager.default.removeItem(atPath: path)

        let model = StudioModel()
        model.prompt = "Write the literal sentence Native frontend backend integration passed to \(path)"
        await model.generateWorkflowFromBackend()

        precondition(model.hasWorkflow, "Expected a generated executable workflow")
        precondition(model.workflow.executableNode?.runner.steps.isEmpty == false, "Expected runner steps")
        model.approveVersion()
        await model.runLocallyWithBackend()

        precondition(model.runnerStatus == "Complete", "Expected backend execution to complete. Logs: \(model.logs.map(\.message))")
        let written = try String(contentsOfFile: path, encoding: .utf8)
        precondition(written == "Native frontend backend integration passed", "Unexpected file contents: \(written)")
        print("LocalWorkflowStudioNativeIntegrationTests passed")
    }
}
