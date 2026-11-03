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
        /// Peak 100 ms RMS below this counts as silence (-60 dBFS, matching the recording meter).
        /// Quiet interface microphones must still reach the speech model's own no-speech filter.
        public var silenceThreshold: Float = 0.001
        public var pollInterval: Duration = .milliseconds(200)
        /// At stop, transcribe the whole recording in one pass and use that, rather than adding the tail
        /// to what the live passes confirmed. The live passes then only feed the live text.
        public var wholeRecordingAtStop = false

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

    /// Stops background passes, transcribes whatever is left (or everything, with `wholeRecordingAtStop`),
    /// and returns the full transcript.
    public func finish() async throws -> String {
        await stopLoop()
        if configuration.wholeRecordingAtStop { confirmed = [] }
        let tail = source.samples(from: configuration.wholeRecordingAtStop ? 0 : confirmedEndSample)
        if tail.count >= Int(0.3 * configuration.sampleRate) {
            if containsSound(tail) {
                let segments = try await engine.transcribe(tail)
                passCount += 1
                if TranscriptCleaner.hasRepeatedWholeText(TranscriptCleaner.join(segments)) {
                    Log.transcription.warning("Speech engine repeated the entire final pass: \(tail.count) audio samples, \(segments.count) segments")
                }
                confirmed += segments
            } else {
                Log.transcription.notice("Skipped quiet tail: \(tail.count) samples below RMS threshold \(self.configuration.silenceThreshold, privacy: .public)")
            }
        }
        pendingText = ""
        let text = TranscriptCleaner.join(confirmed)
        if TranscriptCleaner.hasRepeatedWholeText(text) {
            Log.transcription.warning("Final transcript repeats its entire text: \(text.count) characters, \(self.passCount) passes, whole-recording \(self.configuration.wholeRecordingAtStop, privacy: .public)")
        }
        return text
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
            // Text is only final when its timestamps also move the audio cursor forward.
            // Otherwise the next pass would transcribe the same audio and append it again.
            var end = 0.0
            let candidates = segments.prefix(segments.count - keep)
            let toConfirm = candidates.prefix { segment in
                guard segment.start.isFinite, segment.end.isFinite,
                      segment.start >= 0, segment.start <= segment.end,
                      segment.end > end, segment.end <= tailSeconds,
                      Int(segment.end * configuration.sampleRate) > Int(end * configuration.sampleRate)
                else { return false }
                end = segment.end
                return true
            }
            if toConfirm.count != candidates.count {
                Log.transcription.warning("Held back \(candidates.count - toConfirm.count) segments with non-advancing or invalid timestamps; tail \(tailLength) samples")
            }
            confirmed += toConfirm
            if let last = toConfirm.last {
                confirmedEndSample += Int(last.end * configuration.sampleRate)
            }
            pendingText = TranscriptCleaner.join(Array(segments.dropFirst(toConfirm.count)))
        } else {
            pendingText = TranscriptCleaner.join(segments)
        }
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
