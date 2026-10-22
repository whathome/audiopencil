import APCore
import APModels
import CoreML
import Foundation
import WhisperKit

public enum WhisperEngineError: LocalizedError {
    case notDownloaded(String)
    case notLoaded

    public var errorDescription: String? {
        switch self {
        case .notDownloaded(let variant): String(localized: "The transcription model \(variant) hasn't been downloaded.", bundle: .module)
        case .notLoaded: String(localized: "The transcription model isn't loaded.", bundle: .module)
        }
    }
}

/// Where a first-time preparation is: Core ML compiling each part of the model for this Mac's Neural
/// Engine. Minutes for large models, and done by a system process, so the app needs to show it's moving.
public struct ModelPreparation: Equatable, Sendable {
    public var variant: String
    /// 1-based step and the number of steps.
    public var step: Int
    public var steps: Int
    /// The part being prepared, e.g. "audio encoder".
    public var part: String
    public var startedAt: Date
    /// Expected total, from earlier runs on this Mac or the model's size.
    public var estimatedSeconds: Double

    public init(variant: String, step: Int, steps: Int, part: String, startedAt: Date, estimatedSeconds: Double) {
        self.variant = variant
        self.step = step
        self.steps = steps
        self.part = part
        self.startedAt = startedAt
        self.estimatedSeconds = estimatedSeconds
    }
}

/// WhisperKit wrapper. Residency is owned by `ModelCoordinator`; call `load`/`unload` only through it.
public actor WhisperEngine: DictationEngine {
    public nonisolated let kind = ModelKind.transcription
    public nonisolated let variant: String
    public nonisolated var displayName: String { "Whisper \(variant)" }
    /// Each live pass confirms text as it goes, so stop only transcribes what is left.
    public nonisolated var transcribesWholeRecordingAtStop: Bool { false }

    private let root: URL
    private var kit: WhisperKit?
    private var vocabulary: [String] = []
    /// Whisper code of the language to transcribe. English-only models always get "en".
    private var language = "en"
    /// Serialises loads, unloads and transcriptions: WhisperKit isn't safe to use concurrently.
    private let lock = AsyncLock()

    public init(variant: String, root: URL = ModelLocations.root) {
        self.variant = variant
        self.root = root
    }

    public var isLoaded: Bool { kit != nil }

    /// How far a whole-recording pass in progress has got, 0…1 (meeting labels go over every word again).
    public var transcriptionProgress: Double { kit?.progress.fractionCompleted ?? 0 }

    /// Terms passed to Whisper as prompt context so they're spelled correctly.
    public func setVocabulary(_ words: [String]) {
        vocabulary = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// One language per recording: set before it starts (or before re-transcribing after a switch).
    public func setLanguage(_ code: String) {
        language = DictationSettings.isEnglishOnly(variant) ? "en" : code
    }

    private nonisolated var folder: URL { ModelLocations.whisperFolder(variant: variant, root: root) }

    /// True when the model files are on disk (no network needed to load).
    public nonisolated var isDownloaded: Bool {
        ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { name in
            FileManager.default.fileExists(atPath: folder.appending(path: "\(name).mlmodelc").path)
        }
    }

    /// True until the first successful load has compiled the model for this Mac.
    public nonisolated var needsFirstTimePreparation: Bool {
        !FileManager.default.fileExists(atPath: prewarmMarker.path)
    }

    private nonisolated var prewarmMarker: URL { folder.appending(path: ".audiopencil-prewarmed") }

    /// Downloads the model from Hugging Face. `progress` receives 0…1.
    public func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        Log.models.info("Downloading \(self.variant, privacy: .public)")
        _ = try await WhisperKit.download(
            variant: variant,
            downloadBase: root,
            from: ModelLocations.whisperRepository
        ) { value in
            progress(value.fractionCompleted)
        }
    }

    public func load() async throws {
        guard isDownloaded else { throw WhisperEngineError.notDownloaded(variant) }
        try await lock.withLock {
            guard kit == nil else { return }
            try await createKit()
        }
    }

    private func createKit() async throws {
        // The first load compiles the model for the Neural Engine, which can take minutes. Done here one
        // part at a time, exactly as WhisperKit's prewarm would (same parts, order and compute units), so
        // progress can be shown and WhisperKit's own load below finds everything compiled.
        if needsFirstTimePreparation {
            try await prepare()
            FileManager.default.createFile(atPath: prewarmMarker.path, contents: nil)
        }

        let config = WhisperKitConfig(
            downloadBase: root,
            modelFolder: folder.path,
            tokenizerFolder: root,
            computeOptions: Self.computeOptions,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        kit = try await WhisperKit(config)
    }

    /// True once this model is downloaded and prepared for this Mac: loading it takes seconds.
    public nonisolated var isReady: Bool { isDownloaded && !needsFirstTimePreparation }

    /// Prepares the model for this Mac without loading it for use, so it can run in the background
    /// while another model is loaded. The compiling happens in a system process; nothing stays resident.
    public func prepareIfNeeded() async throws {
        guard isDownloaded, needsFirstTimePreparation else { return }
        try await lock.withLock {
            guard needsFirstTimePreparation else { return }
            try await prepare()
            FileManager.default.createFile(atPath: prewarmMarker.path, contents: nil)
        }
    }

    /// Called as each part of a first-time preparation starts. Set before loading.
    private var onPreparation: (@Sendable (ModelPreparation?) -> Void)?

    public func setPreparationHandler(_ handler: (@Sendable (ModelPreparation?) -> Void)?) {
        onPreparation = handler
    }

    /// WhisperKit's defaults, except that on iOS the audio features (mel spectrogram) run on the CPU: iOS
    /// refuses GPU work in the background, and recording keeps transcribing with the phone locked. The model
    /// is tiny, so the CPU costs nothing noticeable.
    static var computeOptions: ModelComputeOptions {
        #if os(iOS)
        ModelComputeOptions(melCompute: .cpuOnly)
        #else
        ModelComputeOptions()
        #endif
    }

    private func prepare() async throws {
        let compute = Self.computeOptions
        let parts: [(file: String, name: String, units: MLComputeUnits)] = [
            ("MelSpectrogram", String(localized: "audio features", bundle: .module), compute.melCompute),
            ("TextDecoder", String(localized: "text decoder", bundle: .module), compute.textDecoderCompute),
            ("AudioEncoder", String(localized: "audio encoder", bundle: .module), compute.audioEncoderCompute),
        ]
        let estimate = PreparationEstimate.seconds(variant: variant, folder: folder)
        let start = Date()
        for (index, part) in parts.enumerated() {
            onPreparation?(ModelPreparation(variant: variant, step: index + 1, steps: parts.count, part: part.name, startedAt: start, estimatedSeconds: estimate))
            let configuration = MLModelConfiguration()
            configuration.computeUnits = part.units
            let url = ModelUtilities.detectModelURL(inFolder: folder, named: part.file)
            _ = try await MLModel.load(contentsOf: url, configuration: configuration) // compiled, cached, released
        }
        let seconds = Date().timeIntervalSince(start)
        // Seconds mean Core ML already had it compiled (a cache hit), which says nothing about a real run.
        if seconds > 10 { PreparationEstimate.record(seconds, variant: variant) }
        Log.models.notice("Prepared \(self.variant, privacy: .public) for this device in \(Int(seconds)) s (estimated \(Int(estimate)) s)")
        onPreparation?(nil)
    }

    public func unload() async {
        try? await lock.withLock {
            await kit?.unloadModels()
            kit = nil
        }
    }

    public func transcribe(_ samples: [Float]) async throws -> [TranscriptSegment] {
        try await lock.withLock {
            try await runTranscription(samples)
        }
    }

    /// The whole recording in one go, with word timings, for meeting mode's speaker labels. Long audio
    /// is split at pauses. No vocabulary prompt: with word timings, a prompt makes Whisper skip the
    /// opening segment (seen on a real recording); the writing model gets the spellings instead.
    public func transcribeTimedWords(_ samples: [Float]) async throws -> [TimedWord] {
        try await lock.withLock {
            guard let kit else { throw WhisperEngineError.notLoaded }
            var options = options(prompt: nil, noSpeechThreshold: 0.6)
            options.wordTimestamps = true
            options.chunkingStrategy = .vad
            let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
            let words = results.flatMap(\.segments).flatMap { segment -> [TimedWord] in
                // Without word timings (rare), the segment stands in for its words.
                guard let words = segment.words, !words.isEmpty else {
                    return [TimedWord(text: " " + segment.text, start: Double(segment.start), end: Double(segment.end))]
                }
                return words.map { TimedWord(text: $0.word, start: Double($0.start), end: Double($0.end)) }
            }
            return SpeakerTranscript.withoutSoundLabels(words)
        }
    }

    private func options(prompt: [Int]?, noSpeechThreshold: Float?) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            promptTokens: prompt,
            suppressBlank: true,
            noSpeechThreshold: noSpeechThreshold
        )
    }

    /// At least half a second of 100 ms windows at speaking level (about -30 dBFS RMS).
    static func speechLikely(_ samples: [Float], sampleRate: Int = 16_000) -> Bool {
        let window = sampleRate / 10
        var loud = 0
        var index = 0
        while index + window <= samples.count {
            var sum: Float = 0
            for i in index..<(index + window) { sum += samples[i] * samples[i] }
            if (sum / Float(window)).squareRoot() >= 0.03 { loud += 1 }
            if loud >= 5 { return true }
            index += window
        }
        return false
    }

    private func runTranscription(_ samples: [Float]) async throws -> [TranscriptSegment] {
        guard let kit else { throw WhisperEngineError.notLoaded }

        // Whisper treats the prompt as preceding text, so a short glossary steers spelling.
        // WhisperKit keeps the last 224 prompt tokens and drops special tokens.
        let promptTokens = vocabulary.isEmpty ? nil : kit.tokenizer?.encode(text: " Glossary: " + vocabulary.joined(separator: ", ") + ".")

        var results = try await kit.transcribe(audioArray: samples, decodeOptions: options(prompt: promptTokens, noSpeechThreshold: 0.6))
        #if DEBUG
        Log.models.debug("Whisper [\(self.language, privacy: .public)] \(samples.count / 16_000) s → \(results.flatMap(\.segments).map(\.text).joined(separator: " | "), privacy: .public)")
        #endif
        // Large v3 models sometimes judge real speech to be silence (more so with a prompt) and return
        // nothing, or only a sound label such as "*Bell*". Audio that is clearly speech but came back empty gets one retry without either. Only
        // then: without the filter, Whisper invents text ("Thanks for watching") over real silence.
        if Self.speechLikely(samples), !TranscriptCleaner.hasSpeech(TranscriptCleaner.join(Self.segments(results))) {
            results = try await kit.transcribe(audioArray: samples, decodeOptions: options(prompt: nil, noSpeechThreshold: nil))
            Log.models.notice("Whisper \(self.variant, privacy: .public) [\(self.language, privacy: .public)] heard nothing in \(samples.count / 16_000) s; retried without the no-speech filter: \(TranscriptCleaner.hasSpeech(TranscriptCleaner.join(Self.segments(results))) ? "got text" : "still nothing", privacy: .public)")
        }
        return Self.segments(results)
    }

    private static func segments(_ results: [TranscriptionResult]) -> [TranscriptSegment] {
        results.flatMap(\.segments).map {
            TranscriptSegment(start: Double($0.start), end: Double($0.end), text: $0.text)
        }
    }
}
