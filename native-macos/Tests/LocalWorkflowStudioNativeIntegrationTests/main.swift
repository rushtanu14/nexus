import Foundation
import LocalWorkflowStudioCore

@main
@MainActor
struct IntegrationTestRunner {
    static func main() async throws {
        let path = "/tmp/nexus-native-live-proof.txt"
        try? FileManager.default.removeItem(atPath: path)
        try await clearBackendNodes()

        let model = StudioModel()
        model.prompt = "Write a file. File path: \(path). File content exactly: Native frontend backend integration passed"
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

    private static func clearBackendNodes() async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:3131/node/clear")!)
        request.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "NexusIntegration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not clear backend nodes before integration test"])
        }
    }
}
