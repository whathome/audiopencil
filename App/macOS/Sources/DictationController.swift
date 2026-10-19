import APAudio
import APCore
import APTranscription
import Foundation

/// What happened on the last dictation, for the status window and latency tracking.
struct DictationReport {
    var finishedAt: Date
    var audioSeconds: Double
    /// Stop pressed → transcript ready.
    var stopToText: Duration
    /// Stop pressed → ⌘V posted (or clipboard written).
    var stopToDelivery: Duration
    var outcome: String
    var passes: Int
    var characters: Int
    var preview: String
}

/// Quick-dictation loop: record → stream to Whisper → stop → paste.
@Observable
final class DictationController {
    enum Phase {
        case idle
        /// Waiting for the microphone to come on (only noticeable when it wasn't warmed up).
        case starting
        case recording
        case finishing
    }

    private(set) var phase: Phase = .idle
    private(set) var lastReport: DictationReport?
    private(set) var lastError: String?

    /// Called after a real (not dry-run) dictation delivers text, with its word count and audio length.
    var onDelivered: ((_ words: Int, _ audioSeconds: Double) -> Void)?

    /// Debug builds: skip the paste and log the transcript instead (set by the debug control hook).
    var dryRun = false

    /// Starting, recording or finishing: Escape cancels in any of them.
    var isActive: Bool { phase != .idle }

    private let recorder = AudioRecorder()
    private let cues = CuePlayer()
    private let indicator: IndicatorModel
    private let engine: () -> WhisperEngine
    private let waitForModel: () async throws -> Void

    private var streamer: StreamingTranscriber?
    /// Bumped on every start/cancel so a finishing task can tell it has been cancelled.
    private var generation = 0
    /// Bumped on every warm-up so only the latest one turns the mic back off.
    private var warmGeneration = 0

    init(indicator: IndicatorModel, engine: @escaping () -> WhisperEngine, waitForModel: @escaping () async throws -> Void) {
        self.indicator = indicator
        self.engine = engine
        self.waitForModel = waitForModel
    }

    /// First Fn tap: turn the mic on so a second tap starts recording instantly.
    /// Turns it off again if no recording starts within `seconds`.
    func warmUp(deviceID: UInt32?, seconds: Double = 0.8) {
        guard phase == .idle else { return }
        warmGeneration += 1
        let warm = warmGeneration
        let recorder = self.recorder
        Task {
            try? await recorder.warmUp(deviceID: deviceID)
            try? await Task.sleep(for: .seconds(seconds))
            if warm == warmGeneration, phase == .idle { recorder.stop() }
        }
    }

    func start(microphoneGranted: Bool, deviceID: UInt32?) {
        guard phase == .idle else { return }
        guard microphoneGranted else {
            cues.play(.cancel)
            indicator.flash(.error("Microphone access needed"))
            return
        }

        generation += 1
        let generation = self.generation
        phase = .starting
        let requestedAt = ContinuousClock.now
        let indicator = self.indicator

        Task {
            do {
                try await recorder.beginRecording(
                    deviceID: deviceID,
                    onLevel: { level in Task { @MainActor in indicator.push(level) } },
                    onInterruption: { Task { @MainActor [weak self] in self?.stop() } }
                )
            } catch {
                if generation == self.generation {
                    fail("Couldn't start the microphone: \(error.localizedDescription)")
                }
                return
            }
            guard generation == self.generation else { return } // cancelled while the mic came on

            phase = .recording
            cues.play(.start)
            recorder.muteNext(seconds: 0.3) // keep the start cue out of the transcript
            indicator.show(.listening)

            let engine = self.engine()
            let streamer = StreamingTranscriber(
                engine: engine,
                source: recorder.samples,
                isEngineReady: { await engine.isLoaded },
                onUpdate: { confirmed, pending in
                    Task { @MainActor in indicator.liveText = [confirmed, pending].filter { !$0.isEmpty }.joined(separator: " ") }
                }
            )
            self.streamer = streamer
            await streamer.start()
            Log.dictation.notice("Recording started \(ContinuousClock.now - requestedAt, privacy: .public) after the request")
        }
    }

    func stop() {
        guard phase == .recording, let streamer else { return }
        let stoppedAt = ContinuousClock.now
        phase = .finishing
        recorder.stop()
        cues.play(.stop)
        indicator.show(.processing)
        let audioSeconds = Double(recorder.samples.count) / AudioRecorder.sampleRate
        let generation = self.generation

        Task {
            do {
                if !(await engine().isLoaded) {
                    indicator.show(.preparingModel)
                    try await waitForModel()
                    guard generation == self.generation else { return }
                    indicator.show(.processing)
                }
                let text = try await streamer.finish()
                let textReady = ContinuousClock.now
                guard generation == self.generation else { return } // cancelled while finishing

                let outcome: String
                if text.isEmpty {
                    outcome = "nothing heard"
                    indicator.flash(.nothingHeard)
                } else if dryRun {
                    outcome = "dry run"
                    indicator.hide()
                    Log.dictation.notice("Dry-run transcript: \(text, privacy: .public)")
                } else {
                    let result = Paster.deliver(text)
                    outcome = result.rawValue
                    onDelivered?(UsageStats.wordCount(text), audioSeconds)
                    if result == .clipboardOnly {
                        indicator.flash(.clipboard)
                    } else {
                        indicator.hide()
                    }
                }
                let delivered = ContinuousClock.now
                lastReport = DictationReport(
                    finishedAt: Date(),
                    audioSeconds: audioSeconds,
                    stopToText: textReady - stoppedAt,
                    stopToDelivery: delivered - stoppedAt,
                    outcome: outcome,
                    passes: await streamer.passCount,
                    characters: text.count,
                    preview: String(text.prefix(280))
                )
                lastError = nil
                Log.dictation.notice("Dictation \(outcome, privacy: .public): \(audioSeconds, format: .fixed(precision: 1))s audio, stop→text \(textReady - stoppedAt, privacy: .public), stop→paste \(delivered - stoppedAt, privacy: .public)")
            } catch {
                if generation == self.generation {
                    fail("Transcription failed: \(error.localizedDescription)")
                }
            }
            if generation == self.generation {
                phase = .idle
                self.streamer = nil
            }
        }
    }

    /// Escape: discard immediately, whether recording or finishing.
    func cancel() {
        guard phase != .idle else { return }
        generation += 1
        recorder.stop()
        if let streamer { Task { await streamer.cancel() } }
        streamer = nil
        phase = .idle
        cues.play(.cancel)
        indicator.hide()
        Log.dictation.info("Dictation cancelled")
    }

    private func fail(_ message: String) {
        recorder.stop()
        streamer = nil
        phase = .idle
        lastError = message
        cues.play(.cancel)
        indicator.flash(.error(message), seconds: 3)
        Log.dictation.error("\(message, privacy: .public)")
    }
}
