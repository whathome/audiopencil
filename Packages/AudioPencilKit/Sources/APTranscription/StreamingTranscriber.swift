import APCore
import Foundation

/// Transcribes a recording while it grows, so only a short tail remains when the user stops.
///
/// Each pass transcribes the unconfirmed tail. When a pass returns more segments than
/// `heldBackSegments`, the earlier ones are confirmed (their text is final) and the tail start
/// moves past them. The last segments stay unconfirmed because Whisper may still revise them
/// as more audio arrives. The same approach as WhisperKit's own `AudioStreamTranscriber`,
/// but over our own capture so the app controls the microphone.
public actor StreamingTranscriber {
    public struct Configuration: Sendable {
        public var sampleRate: Double = 16_000
        /// New audio needed before another pass is worth running.
        public var minimumNewAudio: Double = 1.0
        /// Segments kept unconfirmed at the end of each pass.
        public var heldBackSegments: Int = 2
        /// If the unconfirmed tail grows past this, hold back only one segment so passes stay short.
        public var longTail: Double = 20
        /// Peak 100 ms RMS below this counts as silence (about -40 dBFS).
        public var silenceThreshold: Float = 0.01
        public var pollInterval: Duration = .milliseconds(200)

        public init() {}
    }

    private let engine: any SpeechTranscribing
    private let source: any SampleSource
    private let configuration: Configuration
    private let isEngineReady: @Sendable () async -> Bool
    private let onUpdate: @Sendable (_ confirmed: String, _ pending: String) -> Void

    private var confirmed: [TranscriptSegment] = []
    private var confirmedEndSample = 0
    private var samplesAtLastPass = 0
    private var pendingText = ""
    private var loop: Task<Void, Never>?

    public private(set) var passCount = 0

    public init(
        engine: any SpeechTranscribing,
        source: any SampleSource,
        configuration: Configuration = Configuration(),
        isEngineReady: @escaping @Sendable () async -> Bool = { true },
        onUpdate: @escaping @Sendable (_ confirmed: String, _ pending: String) -> Void = { _, _ in }
    ) {
        self.engine = engine
        self.source = source
        self.configuration = configuration
        self.isEngineReady = isEngineReady
        self.onUpdate = onUpdate
    }

    /// Starts background passes. Call `finish()` or `cancel()` to end.
    public func start() {
        guard loop == nil else { return }
        loop = Task { await self.runLoop() }
    }

    /// Stops background passes, transcribes whatever is left, and returns the full transcript.
    public func finish() async throws -> String {
        await stopLoop()
        let tail = source.samples(from: confirmedEndSample)
        if tail.count >= Int(0.3 * configuration.sampleRate), containsSound(tail) {
            let segments = try await engine.transcribe(tail)
            passCount += 1
            confirmed += segments
        }
        pendingText = ""
        return TranscriptCleaner.join(confirmed)
    }

    public func cancel() async {
        await stopLoop()
    }

    /// Runs one pass if enough new audio has arrived. Exposed for tests; the loop calls it.
    @discardableResult
    public func passIfNeeded() async -> Bool {
        let available = source.count
        let newAudio = Double(available - samplesAtLastPass) / configuration.sampleRate
        guard newAudio >= configuration.minimumNewAudio else { return false }
        samplesAtLastPass = available

        let tail = source.samples(from: confirmedEndSample)
        guard containsSound(tail) else { return true }

        do {
            let segments = try await engine.transcribe(tail)
            passCount += 1
            absorb(segments, tailLength: tail.count)
        } catch is CancellationError {
            // Stopping; finish() re-transcribes the tail.
        } catch {
            Log.transcription.error("Streaming pass failed: \(error.localizedDescription, privacy: .public)")
        }
        return true
    }

    private func runLoop() async {
        while !Task.isCancelled {
            if await isEngineReady(), await passIfNeeded() {
                continue
            }
            try? await Task.sleep(for: configuration.pollInterval)
        }
    }

    private func stopLoop() async {
        loop?.cancel()
        await loop?.value
        loop = nil
    }

    private func absorb(_ segments: [TranscriptSegment], tailLength: Int) {
        let tailSeconds = Double(tailLength) / configuration.sampleRate
        let keep = tailSeconds > configuration.longTail ? 1 : configuration.heldBackSegments
        if segments.count > keep {
            let toConfirm = segments.prefix(segments.count - keep)
            confirmed += toConfirm
            if let last = toConfirm.last {
                let advance = Int(last.end * configuration.sampleRate)
                confirmedEndSample += min(max(advance, 0), tailLength)
            }
        }
        pendingText = TranscriptCleaner.join(Array(segments.suffix(min(keep, segments.count))))
        onUpdate(TranscriptCleaner.join(confirmed), pendingText)
    }

    /// True if any 100 ms window is louder than the silence threshold.
    private func containsSound(_ samples: [Float]) -> Bool {
        let window = Int(configuration.sampleRate / 10)
        var index = 0
        while index < samples.count {
            let end = min(index + window, samples.count)
            var sum: Float = 0
            for i in index..<end { sum += samples[i] * samples[i] }
            if (sum / Float(end - index)).squareRoot() >= configuration.silenceThreshold { return true }
            index = end
        }
        return false
    }
}
