import AVFoundation
import AppKit
import Foundation
import Observation
import Speech
import LocalWorkflowStudioCore

struct EchoSession: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var duration: TimeInterval
    var transcript: String
    var notes: String
    var actions: [EchoMCPAction]

    init(id: UUID, name: String, createdAt: Date, duration: TimeInterval, transcript: String, notes: String, actions: [EchoMCPAction] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.duration = duration
        self.transcript = transcript
        self.notes = notes
        self.actions = actions
    }

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, duration, transcript, notes, actions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        transcript = try container.decode(String.self, forKey: .transcript)
        notes = try container.decode(String.self, forKey: .notes)
        actions = try container.decodeIfPresent([EchoMCPAction].self, forKey: .actions) ?? []
    }
}

struct EchoMCPAction: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: String
    var provider: String
    var title: String
    var summary: String
    var confidence: Double
    var status: String
    var mcp: EchoMCPCall
}

struct EchoMCPCall: Codable, Equatable {
    var server: String
    var tool: String
    var inputs: [String: String]
}

private struct EchoActionResponse: Decodable {
    var actions: [EchoMCPAction]
    var memory_status: String?
}

private struct EchoActionRunResponse: Decodable {
    var ok: Bool
    var status: String
    var message: String
}

@MainActor
@Observable
final class SpeechTranscriber {
    var transcript = ""
    var status = "Ready"
    var isRecording = false

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finalHandler: ((String) -> Void)?
    private var startHandler: (() -> Void)?
    private var failureHandler: ((String) -> Void)?
    private var hasInputTap = false
    private var silenceTask: Task<Void, Never>?
    private var shouldAutoStopAfterSilence = false
    private var recordingStartedAt: Date?
    private var lastVoiceHeardAt: Date?

    func start(autoStopAfterSilence: Bool = false, onStart: (() -> Void)? = nil, onFailure: ((String) -> Void)? = nil, onFinal: ((String) -> Void)? = nil) {
        guard !isRecording else { return }
        shouldAutoStopAfterSilence = autoStopAfterSilence
        startHandler = onStart
        failureHandler = onFailure
        finalHandler = onFinal
        status = "Requesting permissions"
        Task {
            guard await requestPermissions() else {
                status = "Microphone and speech permissions are required"
                finishStartFailure(status)
                return
            }
            if !startAudio() {
                finishStartFailure(status)
            }
        }
    }

    func stop() {
        guard isRecording || hasInputTap else { return }
        silenceTask?.cancel()
        silenceTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        shouldAutoStopAfterSilence = false
        recordingStartedAt = nil
        lastVoiceHeardAt = nil
        isRecording = false
        status = "Ready"
        finalHandler?(transcript)
        clearHandlers()
    }

    private func finishStartFailure(_ message: String) {
        silenceTask?.cancel()
        silenceTask = nil
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        shouldAutoStopAfterSilence = false
        recordingStartedAt = nil
        lastVoiceHeardAt = nil
        isRecording = false
        failureHandler?(message)
        clearHandlers()
    }

    private func clearHandlers() {
        startHandler = nil
        failureHandler = nil
        finalHandler = nil
    }

    private func requestPermissions() async -> Bool {
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authorization in
                continuation.resume(returning: authorization == .authorized)
            }
        }
        return microphone && speech
    }

    private func startAudio() -> Bool {
        guard let recognizer, recognizer.isAvailable else {
            status = "Speech recognition is unavailable"
            return false
        }
        transcript = ""
        task?.cancel()
        task = nil
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            guard let level = Self.audioLevel(from: buffer), level > -42 else { return }
            Task { @MainActor in
                guard self?.shouldAutoStopAfterSilence == true else { return }
                self?.lastVoiceHeardAt = Date()
            }
        }
        hasInputTap = true
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            recordingStartedAt = Date()
            lastVoiceHeardAt = Date()
            status = "Listening"
            startHandler?()
            startHandler = nil
            startSilenceMonitorIfNeeded()
        } catch {
            status = error.localizedDescription
            return false
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    self?.transcript = result.bestTranscription.formattedString
                    if result.isFinal, self?.shouldAutoStopAfterSilence == false { self?.stop() }
                } else if let error {
                    self?.status = error.localizedDescription
                    self?.stop()
                }
            }
        }
        return true
    }

    private func startSilenceMonitorIfNeeded() {
        guard shouldAutoStopAfterSilence else { return }
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 150_000_000)
                let shouldStop = await MainActor.run {
                    guard let self,
                          self.isRecording,
                          self.shouldAutoStopAfterSilence,
                          !self.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          let recordingStartedAt = self.recordingStartedAt,
                          let lastVoiceHeardAt = self.lastVoiceHeardAt else {
                        return false
                    }
                    let now = Date()
                    return now.timeIntervalSince(recordingStartedAt) >= 1.8 && now.timeIntervalSince(lastVoiceHeardAt) >= 0.85
                }
                if shouldStop {
                    await MainActor.run { self?.stop() }
                    return
                }
            }
        }
    }

    private static func audioLevel(from buffer: AVAudioPCMBuffer) -> Float? {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return nil }
        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        return 20 * log10(max(rms, 0.000_001))
    }
}

@MainActor
final class NexSpeechOutput {
    static let shared = NexSpeechOutput()
    private let synthesizer = AVSpeechSynthesizer()
    private var currentSound: NSSound?

    func speak(_ text: String) {
        stop()
        if speakWithPiper(text) { return }
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        currentSound?.stop()
        currentSound = nil
    }

    private func speakWithPiper(_ text: String) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let model = environment["NEXUS_PIPER_MODEL"],
              FileManager.default.fileExists(atPath: model),
              let executable = piperExecutables().first(where: FileManager.default.isExecutableFile(atPath:)) else {
            return false
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-piper-\(UUID().uuidString).wav")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--model", model, "--output-file", output.path]
        let pipe = Pipe()
        process.standardInput = pipe
        do {
            try process.run()
            pipe.fileHandleForWriting.write(Data(text.utf8))
            pipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return false }
            currentSound = NSSound(contentsOf: output, byReference: false)
            currentSound?.play()
            return true
        } catch {
            return false
        }
    }

    private func piperExecutables() -> [String] {
        var candidates = ["/opt/homebrew/bin/piper", "/usr/local/bin/piper"]
        if let engineRoot = ProcessInfo.processInfo.environment["NEXUS_ENGINE_ROOT"] {
            candidates.append(URL(fileURLWithPath: engineRoot).appendingPathComponent(".venv-piper/bin/piper").path)
        }
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("../.venv-piper/bin/piper").standardized.path)
        return candidates
    }
}

@MainActor
@Observable
final class EchoStore {
    var sessions: [EchoSession]
    var selectedID: UUID?
    var sessionName = ""
    var status = "Ready"
    var dashboardRequest = 0
    let transcriber = SpeechTranscriber()
    private var recordingStartedAt: Date?
    private let defaultsKey = "NexusEchoSessions"

    init() {
        sessions = []
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([EchoSession].self, from: data) {
            sessions = decoded
            if let first = decoded.first {
                selectedID = first.id
                sessionName = first.name
            }
        }
    }

    var selectedSession: EchoSession? {
        sessions.first(where: { $0.id == selectedID })
    }

    var elapsed: TimeInterval {
        guard let recordingStartedAt else { return selectedSession?.duration ?? 0 }
        return (selectedSession?.duration ?? 0) + Date().timeIntervalSince(recordingStartedAt)
    }

    func createEcho() {
        let session = EchoSession(id: UUID(), name: "Untitled Echo", createdAt: Date(), duration: 0, transcript: "", notes: "")
        sessions.insert(session, at: 0)
        selectedID = session.id
        sessionName = session.name
        persist()
    }

    func select(_ session: EchoSession) {
        selectedID = session.id
        sessionName = session.name
    }

    func renameSelected(_ name: String) {
        guard let index = selectedIndex else { return }
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        sessions[index].name = newName.isEmpty ? "Untitled Echo" : newName
        sessionName = sessions[index].name
        persist()

        // Force a refresh of the selectedID to ensure UI updates if needed,
        // though sessions mutation should be enough.
        let currentID = selectedID
        selectedID = nil
        selectedID = currentID
    }

    func deleteSelected() {
        guard let selectedID else { return }
        if transcriber.isRecording { stopRecording() }
        sessions.removeAll(where: { $0.id == selectedID })
        self.selectedID = sessions.first?.id
        sessionName = sessions.first?.name ?? ""
        status = sessions.isEmpty ? "Ready" : "Echo deleted"
        persist()
    }

    func requestDashboard() {
        dashboardRequest += 1
    }

    func toggleRecording() {
        if transcriber.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        if selectedSession == nil { createEcho() }
        status = "Requesting microphone"
        transcriber.start(
            onStart: { [weak self] in
                self?.recordingStartedAt = Date()
                self?.status = "Recording"
            },
            onFailure: { [weak self] message in
                self?.recordingStartedAt = nil
                self?.status = message
            },
            onFinal: { [weak self] transcript in
                self?.saveTranscript(transcript)
            }
        )
    }

    func stopRecording() {
        transcriber.stop()
        saveTranscript(transcriber.transcript)
        status = "Ready"
    }

    func pauseRecording() {
        transcriber.stop()
        saveTranscript(transcriber.transcript)
        status = "Paused"
    }

    func makeNoteFromTranscript() {
        guard let index = selectedIndex else { return }
        let source = transcriber.isRecording ? transcriber.transcript : sessions[index].transcript
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = "No transcript to note yet"
            return
        }
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        let addition = "\n\n### Note \(stamp)\n\(trimmed)"
        sessions[index].notes = sessions[index].notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? addition.trimmingCharacters(in: .whitespacesAndNewlines) : sessions[index].notes + addition
        status = "Note added"
        persist()
    }

    func updateNotes(_ notes: String) {
        guard let index = selectedIndex else { return }
        sessions[index].notes = notes
        persist()
    }

    func polishNotes(using model: StudioModel) {
        guard let sessionID = selectedID, let index = selectedIndex else { return }
        saveLiveTranscriptIfNeeded()
        let source = bestPolishSource(for: sessions[index])
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        status = "Nex is polishing notes"
        Task {
            do {
                let polished = try await model.completeWithNex("Polish these meeting notes. Use the transcript if the notes are sparse. Preserve factual content, use clear headings and concise bullets, and infer concrete action items without asking for pasted notes:\n\n\(source)")
                guard let currentIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
                sessions[currentIndex].notes = polished
                status = "Notes polished"
                persist()
                await buildMCPActions()
            } catch {
                status = error.localizedDescription
            }
        }
    }

    func buildMCPActions() async {
        guard let index = selectedIndex else { return }
        saveLiveTranscriptIfNeeded()
        let session = sessions[index]
        let source = bestPolishSource(for: session)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "No Echo context for MCP actions yet"
            return
        }
        status = "Nex is building MCP actions"
        do {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:3131/echo/actions")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONEncoder().encode([
                "title": session.name,
                "transcript": session.transcript.isEmpty ? transcriber.transcript : session.transcript,
                "notes": source,
                "project": "nexus"
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw NSError(domain: "NexusEcho", code: 1, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "Could not build Echo MCP actions"])
            }
            let decoded = try JSONDecoder().decode(EchoActionResponse.self, from: data)
            guard let currentIndex = selectedIndex else { return }
            sessions[currentIndex].actions = decoded.actions
            status = decoded.actions.isEmpty ? "No MCP actions inferred yet" : "MCP actions ready"
            persist()
        } catch {
            status = error.localizedDescription
        }
    }

    func runAction(_ action: EchoMCPAction) {
        Task {
            do {
                var request = URLRequest(url: URL(string: "http://127.0.0.1:3131/echo/action/run")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "content-type")
                request.httpBody = try JSONEncoder().encode(["action": action])
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw NSError(domain: "NexusEcho", code: 1, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "Could not prepare MCP action"])
                }
                let decoded = try JSONDecoder().decode(EchoActionRunResponse.self, from: data)
                updateAction(action.id, status: decoded.status)
                status = decoded.message
            } catch {
                updateAction(action.id, status: "failed")
                status = error.localizedDescription
            }
        }
    }

    private var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return sessions.firstIndex(where: { $0.id == selectedID })
    }

    private func saveTranscript(_ transcript: String) {
        guard let index = selectedIndex else { return }
        sessions[index].transcript = transcript
        if sessions[index].notes.isEmpty { sessions[index].notes = transcript }
        if let recordingStartedAt {
            sessions[index].duration += Date().timeIntervalSince(recordingStartedAt)
            self.recordingStartedAt = nil
        }
        persist()
    }

    private func saveLiveTranscriptIfNeeded() {
        let live = transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !live.isEmpty, let index = selectedIndex else { return }
        sessions[index].transcript = live
        if sessions[index].notes.isEmpty { sessions[index].notes = live }
        persist()
    }

    private func bestPolishSource(for session: EchoSession) -> String {
        let liveTranscript = transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcript = session.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = session.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !liveTranscript.isEmpty, notesIsPlaceholder(notes) || notes.count < 40 { return liveTranscript }
        if !notes.isEmpty, !notesIsPlaceholder(notes) { return notes }
        if !transcript.isEmpty { return transcript }
        return liveTranscript
    }

    private func notesIsPlaceholder(_ notes: String) -> Bool {
        let lower = notes.lowercased()
        return lower.contains("please paste the meeting notes") || lower.contains("ready to polish them")
    }

    private func updateAction(_ id: UUID, status: String) {
        guard let sessionIndex = selectedIndex,
              let actionIndex = sessions[sessionIndex].actions.firstIndex(where: { $0.id == id }) else { return }
        sessions[sessionIndex].actions[actionIndex].status = status
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

@MainActor
@Observable
final class NexVoiceStore {
    var isVisible = true
    var response = "Ask Nex with your voice."
    var requestedSection: String?
    var requestedAutomation: String?
    let transcriber = SpeechTranscriber()

    func toggle(using model: StudioModel) {
        if transcriber.isRecording {
            transcriber.stop()
        } else {
            NexSpeechOutput.shared.stop()
            transcriber.start(autoStopAfterSilence: true, onFinal: { [weak self] transcript in
                guard !transcript.isEmpty else { return }
                self?.response = "Thinking..."
                Task {
                    do {
                        if let spoken = self?.route(transcript, using: model) {
                            self?.response = spoken
                            NexSpeechOutput.shared.speak(spoken)
                            return
                        }
                        let reply = try await model.completeWithNex(transcript)
                        self?.response = reply
                        NexSpeechOutput.shared.speak(reply)
                    } catch {
                        self?.response = error.localizedDescription
                    }
                }
            })
        }
    }

    func startListening(using model: StudioModel) {
        isVisible = true
        NexSpeechOutput.shared.stop()
        if !transcriber.isRecording { toggle(using: model) }
    }

    private func route(_ prompt: String, using model: StudioModel) -> String? {
        let lower = prompt.lowercased()
        if lower.contains("echo") || lower.contains("meeting") || lower.contains("notes") { requestedSection = "echo"; return nil }
        else if lower.contains("brain") || lower.contains("model") { requestedSection = "brain"; return nil }
        else if lower.contains("hub") || lower.contains("workflow list") { requestedSection = "hub"; return nil }
        else if lower.contains("clear canvas") { model.clearCanvas(); requestedSection = "workflows"; return "Yes, I cleared the canvas." }
        else if lower.contains("delete selected node") || lower.contains("remove selected node") { model.deleteSelectedCanvasNode(); requestedSection = "workflows"; return "Yes, I removed the selected node." }
        else if lower.contains("automation") || lower.contains("node") || lower.contains("nexspace") {
            requestedSection = "workflows"
            requestedAutomation = prompt
            if needsWebsiteLink(prompt) {
                return "I can build that automation. Which exact website link should I use?"
            }
            model.prompt = prompt
            model.generateWorkflow()
            return automationProcessSummary(prompt)
        }
        return nil
    }

    private func needsWebsiteLink(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        guard lower.contains("website") || lower.contains("site") || lower.contains("web app") else { return false }
        return !lower.contains("http://") && !lower.contains("https://") && !lower.contains(".com") && !lower.contains(".org") && !lower.contains(".net") && !lower.contains(".io")
    }

    private func automationProcessSummary(_ prompt: String) -> String {
        let compact = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Yes, I'll get on \(compact) by turning it into a local workflow, routing it through the automation builder, and showing the editable node before anything runs."
    }
}
