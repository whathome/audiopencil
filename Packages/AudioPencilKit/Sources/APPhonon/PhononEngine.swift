import APCore
import APModels
import APTranscription
import FluidAudio
import Foundation

/// Phonon-2 through FluidAudio, on the Neural Engine: FermionResearch's 2-bit retrain of Parakeet TDT 0.6B v3
/// (CC-BY-4.0). English only, and no vocabulary prompt. On an M1 it made a quarter to 40% fewer errors than
/// Whisper Small (English) and ran 5–6× faster (docs/benchmarks/phonon-2-vs-whisper-small.md). A trial, on
/// the Mac only. Residency is owned by `ModelCoordinator`; call `load`/`unload` only through it.
public actor PhononEngine: DictationEngine {
    public static let variant = "fluidinference_phonon-2"

    public nonisolated let kind = ModelKind.transcription
    public nonisolated var variant: String { Self.variant }
    public nonisolated var displayName: String { "Phonon-2" }
    /// One pass over 5 minutes of audio takes under 2 s, and is more accurate than the live passes joined up.
    public nonisolated var transcribesWholeRecordingAtStop: Bool { true }

    private let folder: URL
    private var manager: AsrManager?
    private var onPreparation: (@Sendable (ModelPreparation?) -> Void)?
    /// Serialises loads, unloads and transcriptions.
    private let lock = AsyncLock()

    public init(root: URL = ModelLocations.root) {
        folder = root.appending(path: "phonon-2", directoryHint: .isDirectory)
    }

    public var isLoaded: Bool { manager != nil }

    public nonisolated var isDownloaded: Bool {
        AsrModels.modelsExist(at: folder, version: .phonon2)
    }

    public nonisolated var needsFirstTimePreparation: Bool {
        !FileManager.default.fileExists(atPath: prewarmMarker.path)
    }

    private nonisolated var prewarmMarker: URL { folder.appending(path: ".audiopencil-prewarmed") }

    public func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        Log.models.info("Downloading \(self.variant, privacy: .public)")
        try await AsrModels.download(to: folder, version: .phonon2) { value in
            progress(value.fractionCompleted)
        }
    }

    public func setVocabulary(_ words: [String]) {
        if !words.isEmpty { Log.models.notice("Phonon-2 has no vocabulary prompt; \(words.count) terms ignored") }
    }

    public func setLanguage(_ code: String) {}

    public func setPreparationHandler(_ handler: (@Sendable (ModelPreparation?) -> Void)?) {
        onPreparation = handler
    }

    public func load() async throws {
        guard isDownloaded else { throw WhisperEngineError.notDownloaded(variant) }
        try await lock.withLock {
            guard manager == nil else { return }
            // The first load compiles the encoder for the Neural Engine once per window size (5, 10 and 15 s):
            // about 5 minutes on an M1, in a system process. One step, with the clock and estimate.
            let firstTime = needsFirstTimePreparation
            let start = Date()
            if firstTime {
                let estimate = PreparationEstimate.seconds(variant: variant, folder: folder)
                onPreparation?(ModelPreparation(variant: variant, step: 1, steps: 1, part: String(localized: "speech model", bundle: .module), startedAt: start, estimatedSeconds: estimate))
            }
            do {
                let models = try await AsrModels.load(from: folder, version: .phonon2)
                let manager = AsrManager()
                try await manager.loadModels(models)
                self.manager = manager
            } catch {
                if firstTime { onPreparation?(nil) }
                throw error
            }
            if firstTime {
                FileManager.default.createFile(atPath: prewarmMarker.path, contents: nil)
                let seconds = Date().timeIntervalSince(start)
                if seconds > 10 { PreparationEstimate.record(seconds, variant: variant) }
                Log.models.notice("Prepared \(self.variant, privacy: .public) for this device in \(Int(seconds)) s")
                onPreparation?(nil)
            }
        }
    }

    public func unload() async {
        try? await lock.withLock {
            await manager?.cleanup()
            manager = nil
        }
    }

    public func transcribe(_ samples: [Float]) async throws -> [TranscriptSegment] {
        try await lock.withLock {
            Self.sentences(try await words(samples))
        }
    }

    public func transcribeTimedWords(_ samples: [Float]) async throws -> [TimedWord] {
        try await lock.withLock {
            SpeakerTranscript.withoutSoundLabels(try await words(samples).map {
                TimedWord(text: " " + $0.word, start: $0.startTime, end: $0.endTime)
            })
        }
    }

    /// Long audio is windowed by FluidAudio itself, cut at pauses.
    private func words(_ samples: [Float]) async throws -> [WordTiming] {
        guard let manager else { throw WhisperEngineError.notLoaded }
        // FluidAudio refuses audio under a second; silence after a short word changes nothing.
        let minimum = ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)
        let padded = samples.count < minimum ? samples + [Float](repeating: 0, count: minimum - samples.count) : samples
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(padded, decoderState: &state)
        #if DEBUG
        Log.models.debug("Phonon-2 \(samples.count / 16_000) s → \(result.text, privacy: .public)")
        #endif
        let words = buildWordTimings(from: result.tokenTimings ?? [])
        if words.isEmpty, !result.text.isEmpty {
            // No timings (not expected): the text stands for the whole clip.
            return [WordTiming(word: result.text, startTime: 0, endTime: Double(samples.count) / 16_000)]
        }
        return words
    }

    /// One segment per sentence, so the streaming transcriber confirms whole sentences as they settle.
    static func sentences(_ words: [WordTiming]) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var current: [WordTiming] = []
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            segments.append(TranscriptSegment(start: first.startTime, end: last.endTime, text: current.map(\.word).joined(separator: " ")))
            current = []
        }
        for word in words {
            current.append(word)
            if let end = word.word.last, ".?!".contains(end) { flush() }
        }
        flush()
        return segments
    }
}
