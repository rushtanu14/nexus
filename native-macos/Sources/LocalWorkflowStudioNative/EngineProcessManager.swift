import Foundation
import Darwin

@MainActor
final class EngineProcessManager {
    static let shared = EngineProcessManager()

    private var engineProcess: Process?
    private var ollamaProcess: Process?
    private var lmStudioProcess: Process?

    func startIfNeeded() {
        Task {
            let provider = savedBrainProvider()
            if provider == "lmstudio" {
                startLMStudioServerIfNeeded()
            } else if !(await isReachable(URL(string: "http://127.0.0.1:11434/api/tags")!)) {
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

    private func startLMStudioServerIfNeeded() {
        guard lmStudioProcess == nil,
              let executable = lmStudioExecutable(),
              !isPortOpen(host: "127.0.0.1", port: 1234) else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["server", "start"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        lmStudioProcess = process
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

    private func lmStudioExecutable() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["NEXUS_LMS_PATH"],
            "\(environment["HOME"] ?? NSHomeDirectory())/.lmstudio/bin/lms",
            "/opt/homebrew/bin/lms",
            "/usr/local/bin/lms"
        ].compactMap { $0 }
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }

    private func savedBrainProvider() -> String {
        guard let data = UserDefaults.standard.data(forKey: "NexusBrainConfig"),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let provider = object["provider"] as? String else {
            return "ollama"
        }
        return provider
    }

    private func isPortOpen(host: String, port: UInt16) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        inet_pton(AF_INET, host, &address.sin_addr)
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
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
        return features["echoActions"] as? Bool == true && features["echoRealtime"] as? Bool == true
    }
}
