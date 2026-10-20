import APCore
import APModels
import Foundation
import WhisperKit

public enum WhisperEngineError: LocalizedError {
    case notDownloaded(String)
    case notLoaded

    public var errorDescription: String? {
        switch self {
        case .notDownloaded(let variant): "The transcription model \(variant) hasn't been downloaded."
        case .notLoaded: "The transcription model isn't loaded."
        }
    }
}

/// WhisperKit wrapper. Residency is owned by `ModelCoordinator`; call `load`/`unload` only through it.
public actor WhisperEngine: ManagedModel, SpeechTranscribing {
    public nonisolated let kind = ModelKind.transcription
    public nonisolated let variant: String
    public nonisolated var displayName: String { "Whisper \(variant)" }

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
        // The first load compiles the model for the Neural Engine, which can take minutes.
        // Prewarming does that one model at a time, keeping peak memory down.
        let firstLoad = needsFirstTimePreparation

        let config = WhisperKitConfig(
            downloadBase: root,
            modelFolder: folder.path,
            tokenizerFolder: root,
            verbose: false,
            logLevel: .error,
            prewarm: firstLoad,
            load: true,
            download: false
        )
        kit = try await WhisperKit(config)
        if firstLoad {
            FileManager.default.createFile(atPath: prewarmMarker.path, contents: nil)
        }
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
