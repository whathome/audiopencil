import APAudio
import APCore
import APTranscription
import Foundation

/// What happened on the last dictation, for the status window and latency tracking.
struct DictationReport {
    var finishedAt: Date
    var styleName: String
    var audioSeconds: Double
    /// Stop pressed → transcript ready.
    var stopToText: Duration
    /// Stop pressed → ⌘V posted (or clipboard written). Includes any model swap and rewrite.
    var stopToDelivery: Duration
    /// Model swap plus generation, for styled dictations.
    var rewriteDuration: Duration?
    var outcome: String
    var passes: Int
    var characters: Int
    var preview: String
}

/// Turns a transcript into a style. Implemented by AppModel, which owns model swapping.
/// `progress` gets 0…1 estimates as text streams.
typealias StyleRewriter = (_ transcript: String, _ style: Style, _ progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> String

enum RewriteError: LocalizedError {
    case modelNotDownloaded
    case lowMemory

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded: "The writing model isn't downloaded yet"
        case .lowMemory: "Memory is low"
        }
    }
}

/// A recording past the long-form threshold, handed off for note processing instead of pasting.
struct LongFormCapture {
    var transcript: String
    var samples: [Float]
    var style: Style
    var recorded: Date
    var duration: TimeInterval
}

/// A delivered quick dictation, for the optional "save quick dictations" notes.
struct QuickCapture {
    var text: String
    var transcript: String
    var style: Style
    var recorded: Date
    var duration: TimeInterval
}

/// Quick-dictation loop: record → stream to Whisper → stop → (rewrite in a style) → paste.
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
    /// Style the current recording will be delivered in. Number keys change it while recording.
    private(set) var style: Style = .raw
    /// The style picker is showing after stop (optional, Settings).
    private(set) var isPicking = false

    /// Called after a real (not dry-run) dictation delivers text, with its word count and audio length.
    var onDelivered: ((_ words: Int, _ audioSeconds: Double) -> Void)?
    /// Called when a dictation is delivered in a style, with the app it was dictated into (for per-app defaults).
    var onStyleUsed: ((_ style: Style, _ app: String?) -> Void)?
    /// Show a style picker after stop instead of delivering straight away.
    var pickAfterStop = false
    var pickerAutoConfirm: Double = 1.0
    /// Styles offered by the picker.
    var pickerStyles: [Style] = [] {
        didSet { indicator.styleChoices = pickerStyles }
    }
    /// Recordings at least this long (seconds) become long-form notes instead of pasting.
    var longFormThreshold: Double = 300
    /// Long recording finished and transcribed: make a note from it.
    var onLongForm: ((LongFormCapture) -> Void)?
    /// A quick dictation was delivered (only when saving quick dictations is on).
    var onQuickNote: ((QuickCapture) -> Void)?
    var savesQuickDictations = false
    /// Called when the picker opens with a styled default, so the writing model can start loading early.
    var onPrepareRewrite: ((Style) -> Void)?

    /// Debug builds: skip the paste and log the transcript instead (set by the debug control hook).
    var dryRun = false

    /// Starting, recording or finishing: Escape cancels in any of them.
    var isActive: Bool { phase != .idle }

    private let recorder = AudioRecorder()
    private let cues = CuePlayer()

    /// Applies the sound theme and volume from Settings.
    func setSounds(theme: CueTheme, volume: Double) {
        if cues.theme != theme { cues.setTheme(theme) }
        cues.volume = Float(volume)
    }

    func previewSounds() { cues.preview() }
    private let indicator: IndicatorModel
    private let engine: () -> WhisperEngine
    private let waitForModel: () async throws -> Void
    private let rewrite: StyleRewriter
    /// Frontmost app when recording started: where the text is going.
    private var targetApp: String?
    private var recordingStartedAt = Date()
    private var remembersStyle = true
    private var finishTask: Task<Void, Never>?
    private var pickerContinuation: CheckedContinuation<Style?, Never>?
    private var pickGeneration = 0

    private var streamer: StreamingTranscriber?
    /// Bumped on every start/cancel so a finishing task can tell it has been cancelled.
    private var generation = 0
    /// Bumped on every warm-up so only the latest one turns the mic back off.
    private var warmGeneration = 0
    private var stopWhenStarted = false

    init(
        indicator: IndicatorModel,
        engine: @escaping () -> WhisperEngine,
        waitForModel: @escaping () async throws -> Void,
        rewrite: @escaping StyleRewriter
    ) {
        self.indicator = indicator
        self.engine = engine
        self.waitForModel = waitForModel
        self.rewrite = rewrite
        indicator.onSelectStyle = { [weak self] style in self?.select(style) }
        indicator.onPick = { [weak self] style in self?.pick(style) }
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

    /// `remembersStyle`: false for push-to-talk, which is always raw and shouldn't change per-app defaults.
    func start(microphoneGranted: Bool, deviceID: UInt32?, style: Style, targetApp: String?, remembersStyle: Bool = true) {
        guard phase == .idle else { return }
        guard microphoneGranted else {
            cues.play(.cancel)
            indicator.flash(.error("Microphone access needed"))
            return
        }

        generation += 1
        let generation = self.generation
        stopWhenStarted = false
        self.style = style
        self.targetApp = targetApp
        self.remembersStyle = remembersStyle
        indicator.currentStyle = style
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
            recordingStartedAt = Date()
            cues.play(.start)
            recorder.muteNext(seconds: 0.3) // keep the start cue out of the transcript
            indicator.recordingStartedAt = recordingStartedAt
            indicator.longFormThreshold = longFormThreshold
            indicator.show(.listening)
            markLongForm(after: longFormThreshold, generation: generation)

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
            if stopWhenStarted {
                stopWhenStarted = false
                stop()
            }
        }
    }

    /// Number key while recording: switch the style this dictation will be delivered in.
    func select(_ style: Style) {
        guard phase == .recording || phase == .starting else { return }
        self.style = style
        indicator.currentStyle = style
        Log.dictation.notice("Style: \(style.name, privacy: .public)")
    }

    /// Picker showing: a number key picks that style and confirms.
    func pick(_ style: Style?) {
        guard isPicking else { return }
        isPicking = false
        indicator.picker = nil
        pickerContinuation?.resume(returning: style)
        pickerContinuation = nil
    }

    /// Picker showing: Return confirms the highlighted style.
    func confirmPick() {
        pick(indicator.picker?.selected ?? style)
    }

    /// One soft cue when a recording crosses the long-form threshold, so the switch from paste to note
    /// is never a surprise at stop. The pill shows it too.
    private func markLongForm(after seconds: Double, generation: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, generation == self.generation, phase == .recording else { return }
            cues.play(.mark)
            recorder.muteNext(seconds: 0.4) // keep the cue out of the transcript
        }
    }

    func stop() {
        if phase == .starting {
            // Released before the mic came on (a very short hold): stop as soon as it does.
            stopWhenStarted = true
            return
        }
        guard phase == .recording, let streamer else { return }
        let stoppedAt = ContinuousClock.now
        phase = .finishing
        recorder.stop()
        cues.play(.stop)
        indicator.show(.processing)
        let audioSeconds = Double(recorder.samples.count) / AudioRecorder.sampleRate
        let generation = self.generation
        let targetApp = self.targetApp
        let recorded = recordingStartedAt

        if audioSeconds >= longFormThreshold {
            finishLongForm(streamer: streamer, audioSeconds: audioSeconds, recorded: recorded, generation: generation)
            return
        }

        finishTask = Task {
            do {
                // Transcribe the tail while the (optional) picker is up.
                let engine = self.engine()
                let waitForModel = self.waitForModel
                let transcription = Task { @MainActor () -> String in
                    if !(await engine.isLoaded) { try await waitForModel() }
                    return try await streamer.finish()
                }

                var style = self.style
                if pickAfterStop {
                    // Once the transcript is done (Whisper no longer needed), start swapping in the writing
                    // model if the picker still shows a styled choice.
                    Task { [weak self] in
                        _ = try? await transcription.value
                        guard let self, isPicking, let selected = indicator.picker?.selected, !selected.isRaw else { return }
                        onPrepareRewrite?(selected)
                    }
                    guard let chosen = await choose(default: style), generation == self.generation else {
                        transcription.cancel()
                        return
                    }
                    style = chosen
                    self.style = chosen
                    indicator.show(.processing)
                }

                if !(await engine.isLoaded) { indicator.show(.preparingModel) }
                let heard = try await transcription.value
                let transcript = TranscriptCleaner.hasSpeech(heard) ? heard : ""
                let textReady = ContinuousClock.now
                guard generation == self.generation else { return } // cancelled while finishing

                var text = transcript
                var rewriteDuration: Duration?
                var fallbackNote: String?
                if !transcript.isEmpty, !style.isRaw {
                    indicator.rewriteProgress = 0
                    indicator.show(.rewriting(style.name))
                    let indicator = self.indicator
                    let rewriteStart = ContinuousClock.now
                    do {
                        text = try await rewrite(transcript, style) { progress in indicator.rewriteProgress = progress }
                        rewriteDuration = ContinuousClock.now - rewriteStart
                        if text.isEmpty { text = transcript; fallbackNote = "Rewrite came back empty; pasted raw" }
                    } catch is CancellationError {
                        return
                    } catch {
                        guard generation == self.generation else { return }
                        Log.dictation.error("Rewrite failed: \(error.localizedDescription, privacy: .public)")
                        fallbackNote = "\(error.localizedDescription); pasted raw"
                    }
                    guard generation == self.generation else { return }
                }

                let outcome: String
                if text.isEmpty {
                    outcome = "nothing heard"
                    indicator.flash(.nothingHeard)
                } else if dryRun {
                    outcome = "dry run"
                    indicator.hide()
                    Log.dictation.notice("Dry-run \(style.name, privacy: .public) text: \(text, privacy: .public)")
                } else {
                    let result = Paster.deliver(text)
                    outcome = result.rawValue
                    onDelivered?(UsageStats.wordCount(transcript), audioSeconds)
                    if savesQuickDictations {
                        onQuickNote?(QuickCapture(text: text, transcript: transcript, style: style, recorded: recorded, duration: audioSeconds))
                    }
                    if let fallbackNote {
                        indicator.flash(.error(fallbackNote), seconds: 3)
                    } else if result == .clipboardOnly {
                        indicator.flash(.clipboard)
                    } else {
                        indicator.hide()
                    }
                }
                if !text.isEmpty, remembersStyle { onStyleUsed?(style, targetApp) }
                let delivered = ContinuousClock.now
                lastReport = DictationReport(
                    finishedAt: Date(),
                    styleName: style.name,
                    audioSeconds: audioSeconds,
                    stopToText: textReady - stoppedAt,
                    stopToDelivery: delivered - stoppedAt,
                    rewriteDuration: rewriteDuration,
                    outcome: outcome,
                    passes: await streamer.passCount,
                    characters: text.count,
                    preview: String(text.prefix(600))
                )
                lastError = fallbackNote
                Log.dictation.notice("Dictation \(outcome, privacy: .public) [\(style.name, privacy: .public)]: \(audioSeconds, format: .fixed(precision: 1))s audio, stop→text \(textReady - stoppedAt, privacy: .public), rewrite \(rewriteDuration.map { "\($0)" } ?? "–", privacy: .public), stop→paste \(delivered - stoppedAt, privacy: .public)")
            } catch {
                if generation == self.generation {
                    fail("Transcription failed: \(error.localizedDescription)")
                }
            }
            if generation == self.generation {
                phase = .idle
                self.streamer = nil
                indicator.currentStyle = nil
            }
        }
    }

    /// Long recording: no paste. Finish the transcript, hand the recording off, and say so.
    private func finishLongForm(streamer: StreamingTranscriber, audioSeconds: Double, recorded: Date, generation: Int) {
        let samples = recorder.samples.samples(from: 0)
        let style = self.style
        finishTask = Task {
            do {
                let engine = self.engine()
                if !(await engine.isLoaded) {
                    indicator.show(.preparingModel)
                    try await waitForModel()
                }
                let transcript = try await streamer.finish()
                guard generation == self.generation else { return }
                if !TranscriptCleaner.hasSpeech(transcript) {
                    // Nothing to summarise: a stray "." must not become a note written by the model.
                    indicator.flash(.nothingHeard)
                } else if dryRun {
                    Log.dictation.notice("Dry-run long-form [\(style.name, privacy: .public)]: \(transcript.count) characters")
                    onLongForm?(LongFormCapture(transcript: transcript, samples: samples, style: style, recorded: recorded, duration: audioSeconds))
                    indicator.flash(.notice("Long recording: making a note"), seconds: 2.5)
                } else {
                    onLongForm?(LongFormCapture(transcript: transcript, samples: samples, style: style, recorded: recorded, duration: audioSeconds))
                    indicator.flash(.notice("Long recording: making a note"), seconds: 2.5)
                }
                Log.dictation.notice("Long-form recording handed off: \(audioSeconds, format: .fixed(precision: 0))s")
            } catch {
                if generation == self.generation { fail("Transcription failed: \(error.localizedDescription)") }
            }
            if generation == self.generation {
                phase = .idle
                self.streamer = nil
                indicator.currentStyle = nil
            }
        }
    }

    /// Shows the style picker and waits for a choice, auto-confirming the default after `pickerAutoConfirm`.
    private func choose(default style: Style) async -> Style? {
        isPicking = true
        pickGeneration += 1
        let pickGeneration = self.pickGeneration
        indicator.picker = .init(styles: pickerStyles, selected: style, autoConfirm: pickerAutoConfirm)
        indicator.show(.picking)
        let deadline = pickerAutoConfirm
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(deadline))
            guard let self, pickGeneration == self.pickGeneration else { return } // an older picker's timer
            confirmPick()
        }
        return await withCheckedContinuation { pickerContinuation = $0 }
    }

    /// Escape: discard immediately, whether recording or finishing.
    func cancel() {
        guard phase != .idle else { return }
        generation += 1
        finishTask?.cancel()
        finishTask = nil
        if isPicking { pick(nil) }
        indicator.currentStyle = nil
        recorder.stop()
        if let streamer { Task { await streamer.cancel() } }
        streamer = nil
        phase = .idle
        cues.play(.cancel)
        indicator.hide()
        Log.dictation.info("Dictation cancelled")
    }

    private func fail(_ message: String) {
        indicator.currentStyle = nil
        recorder.stop()
        streamer = nil
        phase = .idle
        lastError = message
        cues.play(.cancel)
        indicator.flash(.error(message), seconds: 3)
        Log.dictation.error("\(message, privacy: .public)")
    }
}
