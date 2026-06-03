import Foundation

@MainActor
final class EngineProcessManager {
    static let shared = EngineProcessManager()

    private var engineProcess: Process?
    private var ollamaProcess: Process?

    func startIfNeeded() {
        Task {
            if !(await isReachable(URL(string: "http://127.0.0.1:11434/api/tags")!)) {
                startOllama()
            }
            if !(await isEngineCompatible()) {
                stopExistingEngine()
                startEngine()
            }
        }
    }

    private func startOllama() {
        guard ollamaProcess == nil, let executable = ollamaExecutable() else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        ollamaProcess = process
    }

    private func startEngine() {
        guard engineProcess == nil, let root = engineRoot() else { return }
        let process = Process()
        let script = root.appendingPathComponent("src/server.js").path
        if let executable = nodeExecutable() {
            process.executableURL = executable
            process.arguments = [script]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", script]
        }
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["NEXUS_NODE_STORE"] = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Nexus/nodes.sqlite")
            .path
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        engineProcess = process
    }

    private func stopExistingEngine() {
        engineProcess?.terminate()
        engineProcess = nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", "src/server.js"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.25)
    }

    private func engineRoot() -> URL? {
        let fileManager = FileManager.default
        if let configured = ProcessInfo.processInfo.environment["NEXUS_ENGINE_ROOT"] {
            return URL(fileURLWithPath: configured)
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("engine"),
           fileManager.fileExists(atPath: bundled.appendingPathComponent("src/server.js").path) {
            return bundled
        }
        let parent = URL(fileURLWithPath: fileManager.currentDirectoryPath).deletingLastPathComponent()
        if fileManager.fileExists(atPath: parent.appendingPathComponent("src/server.js").path) {
            return parent
        }
        return nil
    }

    private func ollamaExecutable() -> URL? {
        ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"].first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }

    private func nodeExecutable() -> URL? {
        ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
            .first(where: FileManager.default.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }

    private func isReachable(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    private func isEngineCompatible() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:3131/health")!)
        request.timeoutInterval = 0.5
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = payload["features"] as? [String: Any] else {
            return false
        }
        return features["echoActions"] as? Bool == true
    }
}
