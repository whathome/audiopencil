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

    private func runTranscription(_ samples: [Float]) async throws -> [TranscriptSegment] {
        guard let kit else { throw WhisperEngineError.notLoaded }

        // Whisper treats the prompt as preceding text, so a short glossary steers spelling.
        // WhisperKit keeps the last 224 prompt tokens and drops special tokens.
        let promptTokens = vocabulary.isEmpty ? nil : kit.tokenizer?.encode(text: " Glossary: " + vocabulary.joined(separator: ", ") + ".")

        let options = DecodingOptions(
            task: .transcribe,
            language: "en",
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            promptTokens: promptTokens,
            suppressBlank: true,
            noSpeechThreshold: 0.6
        )
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        return results.flatMap(\.segments).map {
            TranscriptSegment(start: Double($0.start), end: Double($0.end), text: $0.text)
        }
    }
}
