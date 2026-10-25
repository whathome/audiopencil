import APCore
import APModels
import APSummary
import APTranscription
import AVFoundation
import AppKit

/// PRD "Model discovery": checks Hugging Face weekly for models that fit this machine, and lets the
/// user try one against the current model before switching. Nothing switches by itself.
@Observable
final class ModelAdvisor {
    struct TrialLine: Identifiable, Equatable {
        var id: String { label }
        var label: String
        var candidate: String
        var candidateSeconds: Double
        var current: String
        var currentSeconds: Double
        /// Transcription trials: word error rate against the script (lower is better).
        var candidateWER: Double?
        var currentWER: Double?
    }

    enum Trial: Equatable {
        case downloading(Double)
        case testing(String)
        case done([TrialLine])
        case failed(String)
    }

    let machine = MachineProfile.current
    private(set) var suggestions: [ModelSuggestion] = []
    private(set) var lastChecked: Date?
    private(set) var checking = false
    private(set) var checkError: String?
    private(set) var trials: [String: Trial] = [:]

    @ObservationIgnored private unowned let app: AppModel
    @ObservationIgnored private var dismissed: Set<String>

    init(app: AppModel) {
        self.app = app
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "modelSuggestions"), let saved = try? JSONDecoder().decode([ModelSuggestion].self, from: data) {
            suggestions = saved
        }
        lastChecked = defaults.object(forKey: "modelSuggestionsChecked") as? Date
        dismissed = Set(defaults.stringArray(forKey: "modelSuggestionsDismissed") ?? [])
    }

    /// Weekly, quietly in the background.
    func checkIfDue() {
        guard !checking, (lastChecked.map { Date().timeIntervalSince($0) > 7 * 86_400 } ?? true) else { return }
        Task { await check() }
    }

    func check() async {
        checking = true
        checkError = nil
        defer { checking = false }
        do {
            let knownWriting = Set(WritingModelOption.catalogue.map(\.id)).union(dismissed).union([app.settings.writingModel])
            async let writing = WritingModelDiscovery.suggestions(for: machine, excluding: knownWriting)
            async let transcription = TranscriptionModelDiscovery.suggestions(
                for: machine,
                current: app.settings.transcriptionModel,
                multilingualCurrent: app.isMultilingual ? app.settings.multilingualTranscriptionModel : nil
            )
            let found = try await transcription.filter { !dismissed.contains($0.id) } + writing
            suggestions = found
            lastChecked = Date()
            let defaults = UserDefaults.standard
            defaults.set(try? JSONEncoder().encode(found), forKey: "modelSuggestions")
            defaults.set(lastChecked, forKey: "modelSuggestionsChecked")
            Log.models.notice("Model discovery: \(found.count) suggestions for \(self.machine.summary, privacy: .public)")
        } catch {
            checkError = String(localized: "Couldn't reach Hugging Face: \(error.localizedDescription)")
        }
    }

    func dismiss(_ suggestion: ModelSuggestion) {
        dismissed.insert(suggestion.id)
        UserDefaults.standard.set(Array(dismissed), forKey: "modelSuggestionsDismissed")
        suggestions.removeAll { $0.id == suggestion.id }
        trials[suggestion.id] = nil
    }

    /// Switch to the suggestion (the user's explicit approval).
    func adopt(_ suggestion: ModelSuggestion) {
        switch suggestion.kind {
        case .writing: app.settings.writingModel = suggestion.id
        case .transcription: app.settings.transcriptionModel = suggestion.id
        case .multilingualTranscription: app.settings.multilingualTranscriptionModel = suggestion.id
        }
        suggestions.removeAll { $0.id == suggestion.id }
    }

    // MARK: Trials

    /// Downloads the suggestion and runs it next to the current model on the same material.
    func tryOut(_ suggestion: ModelSuggestion) {
        guard app.dictation.phase == .idle, !app.meetings.isProcessing else {
            Log.models.notice("Model trial deferred while dictation or meeting processing is active")
            return
        }
        trials[suggestion.id] = .downloading(0)
        Task {
            do {
                let lines = switch suggestion.kind {
                case .writing: try await tryWriting(suggestion)
                case .transcription, .multilingualTranscription: try await tryTranscription(suggestion)
                }
                trials[suggestion.id] = .done(lines)
            } catch {
                trials[suggestion.id] = .failed(error.localizedDescription)
            }
            app.restoreWhisper()
        }
    }

    private func progress(_ id: String) -> @Sendable (Double) -> Void {
        { fraction in Task { @MainActor [weak self] in self?.trials[id] = .downloading(fraction) } }
    }

    private func tryWriting(_ suggestion: ModelSuggestion) async throws -> [TrialLine] {
        let candidate = SummaryEngine(modelID: suggestion.id)
        if !candidate.isDownloaded { try await candidate.download(progress: progress(suggestion.id)) }
        let cases: [(String, String, Style)] = [
            (String(localized: "Quick note → Polished"), BenchmarkFixtures.lateReport, .polished),
            (String(localized: "Diary → Diary"), BenchmarkFixtures.diary, .diary),
        ]
        func run(_ engine: SummaryEngine, name: String) async throws -> [(String, Double)] {
            trials[suggestion.id] = .testing(String(localized: "Loading \(name)…"))
            try await app.coordinator.ensureLoaded(engine)
            var results: [(String, Double)] = []
            for (label, transcript, style) in cases {
                trials[suggestion.id] = .testing("\(name): \(label)…")
                let prompt = PromptBuilder.prompt(for: style, transcript: transcript, context: .quick)
                let start = ContinuousClock.now
                let output = try await engine.generate(instructions: prompt.instructions, input: prompt.input, maxTokens: prompt.maxTokens)
                results.append((OutputCleaner.clean(output.text), seconds(ContinuousClock.now - start)))
            }
            return results
        }
        let new = try await run(candidate, name: suggestion.name)
        let current = app.writing.isDownloaded ? try await run(app.writing, name: "current model") : cases.map { _ in ("(current model not downloaded)", 0) }
        await app.coordinator.unload(candidate)
        return cases.indices.map { index in
            TrialLine(label: cases[index].0, candidate: new[index].0, candidateSeconds: new[index].1, current: current[index].0, currentSeconds: current[index].1)
        }
    }

    private func tryTranscription(_ suggestion: ModelSuggestion) async throws -> [TrialLine] {
        let candidate = WhisperEngine(variant: suggestion.id)
        if !candidate.isDownloaded { try await candidate.download(progress: progress(suggestion.id)) }
        trials[suggestion.id] = .testing(String(localized: "Recording a test sentence…"))
        let script = BenchmarkFixtures.speechScript
        let samples = try await Self.synthesise(script)

        func run(_ engine: any DictationEngine, name: String) async throws -> (String, Double) {
            trials[suggestion.id] = .testing(engine.needsFirstTimePreparation ? String(localized: "Preparing \(name) for this Mac (first time, can take a few minutes)…") : String(localized: "Loading \(name)…"))
            try await app.coordinator.ensureLoaded(engine)
            trials[suggestion.id] = .testing("\(name): transcribing…")
            let start = ContinuousClock.now
            let text = TranscriptCleaner.join(try await engine.transcribe(samples))
            return (text, seconds(ContinuousClock.now - start))
        }
        let new = try await run(candidate, name: suggestion.name)
        // Compared with the model it would replace: the English one, or the one for other languages.
        let replaced: any DictationEngine = suggestion.kind == .multilingualTranscription ? WhisperEngine(variant: app.settings.multilingualTranscriptionModel) : app.speech
        if !replaced.isDownloaded { try await replaced.download(progress: progress(suggestion.id)) }
        let current = try await run(replaced, name: "current model")
        await app.coordinator.unload(candidate)
        if replaced !== app.speech { await app.coordinator.unload(replaced) }
        return [TrialLine(
            label: "\(Int(Double(samples.count) / 16_000)) s of speech",
            candidate: new.0, candidateSeconds: new.1, current: current.0, currentSeconds: current.1,
            candidateWER: WordErrorRate.compute(reference: script, hypothesis: new.0),
            currentWER: WordErrorRate.compute(reference: script, hypothesis: current.0)
        )]
    }

    /// The system voice, rendered to 16 kHz mono samples.
    private static func synthesise(_ text: String) async throws -> [Float] {
        try await Task.detached {
            let url = FileManager.default.temporaryDirectory.appending(path: "audiopencil-trial-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: url) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = ["-o", url.path, "--file-format=WAVE", "--data-format=LEF32@16000", text]
            try process.run()
            process.waitUntilExit()
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
            try file.read(into: buffer)
            return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        }.value
    }

    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
