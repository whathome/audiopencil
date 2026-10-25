import APAudio
import APCore
import APModels
import APTranscription
import AppKit
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

/// A recording past the long-form threshold, handed off for note processing instead of pasting.
struct LongFormCapture {
    var transcript: String
    var samples: [Float]
    var style: Style
    var language: SpokenLanguage
    var recorded: Date
    var duration: TimeInterval
    /// Meeting mode: label who spoke, `speakers` people if known.
    var meeting = false
    var speakers: Int?
    /// Link the note in that day's daily note.
    var dailyNote = false
}

/// A delivered quick dictation, for the optional "save quick dictations" notes.
struct QuickCapture {
    var text: String
    var transcript: String
    var style: Style
    var language: SpokenLanguage
    var recorded: Date
    var duration: TimeInterval
}

/// Quick-dictation loop: record → stream to the speech model → stop → (rewrite in a style) → paste.
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
    /// The last delivered dictation in full, for "Copy Last Dictation". Memory only.
    private(set) var lastText: String?
    let paster = Paster()
    private(set) var lastIssue: DictationIssue?
    /// Style the current recording will be delivered in. Number keys change it while recording.
    private(set) var style: Style = .raw
    /// Language of the current recording. One per recording; switching restarts transcription.
    private(set) var language: SpokenLanguage = .english
    /// The style picker is showing after stop (optional, Settings).
    private(set) var isPicking = false

    /// Called after a real (not dry-run) dictation delivers text, with its word count and audio length.
    var onDelivered: ((_ words: Int, _ audioSeconds: Double) -> Void)?
    /// Called when a dictation is delivered in a style, with the app it was dictated into (for per-app defaults).
    var onStyleUsed: ((_ style: Style, _ app: String?) -> Void)?
    /// A dictation in `language` finished in `app` (remembered per app on this Mac).
    var onLanguageUsed: ((_ language: SpokenLanguage, _ app: String?) -> Void)?
    /// The language was switched from the pill while recording; the app swaps in the right Whisper
    /// model before `engine()` is asked for it again.
    var onLanguageSelected: ((SpokenLanguage) -> Void)?
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
    /// "New task …": the dictation becomes an Obsidian task line instead of styled text.
    var taskKeywords: [String] = []
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
    private let engine: () -> any DictationEngine
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
        engine: @escaping () -> any DictationEngine,
        waitForModel: @escaping () async throws -> Void,
        rewrite: @escaping StyleRewriter
    ) {
        self.indicator = indicator
        self.engine = engine
        self.waitForModel = waitForModel
        self.rewrite = rewrite
        indicator.onSelectStyle = { [weak self] style in self?.select(style) }
        indicator.onSelectLanguage = { [weak self] language in self?.select(language) }
        indicator.onPick = { [weak self] style in self?.pick(style) }
        indicator.onToggleDelivery = { [weak self] in self?.toggleDelivery() }
        indicator.onSetDelivery = { [weak self] delivery in self?.setDelivery(delivery) }
        indicator.onSetSpeakers = { [weak self] count in self?.setSpeakers(count) }
        indicator.onToggleDailyNote = { [weak self] in self?.toggleDailyNote() }
        indicator.onCyclePushDestination = { [weak self] in self?.cyclePushDestination() }
    }

    /// Push-to-talk text also going to the daily note or a file: (text, where, when it was said).
    var onPushToTalkText: ((String, PushDestination, Date) -> Void)?

    /// The pill's menu: link this recording's note in the daily note, or not.
    func toggleDailyNote() {
        guard phase == .recording || phase == .starting, indicator.dailyNoteAvailable else { return }
        indicator.dailyNoteOverride = !indicator.dailyNote
    }

    /// Push-to-talk, on the pill: paste only → each destination on offer → paste only.
    func cyclePushDestination() {
        guard phase == .recording || phase == .starting, indicator.isPushToTalk else { return }
        let choices = indicator.pushChoices
        guard !choices.isEmpty else { return }
        if let current = indicator.pushDestination, let index = choices.firstIndex(of: current) {
            indicator.pushDestination = index + 1 < choices.count ? choices[index + 1] : nil
        } else {
            indicator.pushDestination = choices.first
        }
        Log.dictation.notice("Push-to-talk also to: \(self.indicator.pushDestination?.label ?? "nothing", privacy: .public)")
    }

    /// Paste, note or meeting, chosen on the pill for this recording; nil decides by length.
    private(set) var deliveryOverride: Delivery?
    /// Meeting: how many people are talking, if the user said.
    private(set) var speakerCount: Int?

    /// The pill's toggle: paste → note → meeting → paste. A short dictation can become a note, a long
    /// one can paste, and either can become a meeting.
    func toggleDelivery() {
        switch indicator.delivery() {
        case .paste: setDelivery(.note)
        case .note: setDelivery(.meeting)
        case .meeting: setDelivery(.paste)
        }
    }

    func setDelivery(_ delivery: Delivery) {
        guard phase == .recording || phase == .starting, !indicator.isPushToTalk else { return }
        deliveryOverride = delivery
        indicator.deliveryOverride = delivery
        Log.dictation.notice("Delivery for this recording: \(delivery.rawValue, privacy: .public)")
    }

    func setSpeakers(_ count: Int?) {
        speakerCount = count
        indicator.speakerCount = count
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
    func start(microphoneGranted: Bool, deviceID: UInt32?, style: Style, language: SpokenLanguage = .english, targetApp: String?, remembersStyle: Bool = true) {
        guard phase == .idle else { return }
        guard microphoneGranted else {
            lastIssue = .microphonePermission
            cues.play(.cancel)
            indicator.showError(String(localized: "Audio Pencil needs microphone access. Click to open Privacy & Security.")) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
            return
        }

        lastIssue = nil
        generation += 1
        let generation = self.generation
        stopWhenStarted = false
        self.style = style
        self.language = language
        self.targetApp = targetApp
        self.remembersStyle = remembersStyle
        // Push-to-talk always pastes, however long it's held; its pill offers where else the text goes.
        deliveryOverride = remembersStyle ? nil : .paste
        indicator.deliveryOverride = deliveryOverride
        speakerCount = nil
        indicator.speakerCount = nil
        indicator.dailyNoteOverride = nil
        indicator.pushDestination = nil
        indicator.isPushToTalk = !remembersStyle // push-to-talk is the raw, unremembered recording
        indicator.currentStyle = style
        indicator.currentLanguage = language
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
                    fail(.microphone(error.localizedDescription))
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

            let streamer = makeStreamer()
            self.streamer = streamer
            await streamer.start()
            Log.dictation.notice("Recording started \(ContinuousClock.now - requestedAt, privacy: .public) after the request")
            if stopWhenStarted {
                stopWhenStarted = false
                stop()
            }
        }
    }

    /// Live transcription of the whole recording so far, in the current engine's language.
    private func makeStreamer() -> StreamingTranscriber {
        let engine = self.engine()
        let indicator = self.indicator
        var configuration = StreamingTranscriber.Configuration()
        configuration.wholeRecordingAtStop = engine.transcribesWholeRecordingAtStop
        return StreamingTranscriber(
            engine: engine,
            source: recorder.samples,
            configuration: configuration,
            isEngineReady: { await engine.isLoaded },
            onUpdate: { confirmed, pending in
                Task { @MainActor in indicator.liveText = [confirmed, pending].filter { !$0.isEmpty }.joined(separator: " ") }
            }
        )
    }

    /// Language chosen in the pill while recording. One language per recording, so what's been said
    /// so far is transcribed again from the start in the new language.
    func select(_ language: SpokenLanguage) {
        guard phase == .recording || phase == .starting, language != self.language else { return }
        self.language = language
        indicator.currentLanguage = language
        onLanguageSelected?(language) // may swap the Whisper model
        Log.dictation.notice("Language: \(language.code, privacy: .public)")
        guard phase == .recording, let old = streamer else { return } // .starting: the streamer is made with the new engine
        let streamer = makeStreamer()
        self.streamer = streamer
        Task {
            await old.cancel()
            await streamer.start()
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
            guard let self, generation == self.generation, phase == .recording, deliveryOverride == nil else { return }
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
        let peak = recorder.samples.samples(from: 0).reduce(Float(0)) { max($0, abs($1)) }
        #if DEBUG
        if dryRun { Self.saveDebugRecording(recorder.samples.samples(from: 0)) }
        #endif
        Log.audio.notice("Stopped: \(audioSeconds, format: .fixed(precision: 1)) s, peak level \(peak, format: .fixed(precision: 3))")
        let generation = self.generation
        let targetApp = self.targetApp
        let recorded = recordingStartedAt

        if deliveryOverride.map({ $0 != .paste }) ?? (audioSeconds >= longFormThreshold) {
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

                if !(await engine.isLoaded) { indicator.show(.preparingModel(firstTime: engine.needsFirstTimePreparation)) }
                let heard = try await transcription.value
                let transcript = TranscriptCleaner.hasSpeech(heard) ? heard : ""
                if transcript.isEmpty { Log.dictation.notice("Nothing heard: raw transcript \(heard.count) characters [\(heard, privacy: .private)]") }
                let textReady = ContinuousClock.now
                guard generation == self.generation else { return } // cancelled while finishing

                var text = transcript
                var rewriteDuration: Duration?
                var fallbackNote: String?
                // "New task: call the landlord by Friday" → "- [ ] Call the landlord by Friday 📅 …", as said.
                let task = TaskKeywords.remainder(of: transcript, keywords: taskKeywords)
                if let task {
                    text = TaskLine.make(task, said: recorded, language: language.code)
                    Log.dictation.notice("Task keyword: pasting a task line")
                }
                if task == nil, !transcript.isEmpty, !style.isRaw {
                    indicator.rewriteProgress = 0
                    indicator.show(.rewriting(style.displayName))
                    let indicator = self.indicator
                    let rewriteStart = ContinuousClock.now
                    do {
                        text = try await rewrite(transcript, style) { progress in indicator.rewriteProgress = progress }
                        rewriteDuration = ContinuousClock.now - rewriteStart
                        if text.isEmpty { text = transcript; fallbackNote = String(localized: "The writing model returned no text.") }
                    } catch is CancellationError {
                        return
                    } catch {
                        guard generation == self.generation else { return }
                        Log.dictation.error("Rewrite failed: \(error.localizedDescription, privacy: .public)")
                        fallbackNote = error.localizedDescription
                    }
                    guard generation == self.generation else { return }
                }

                let outcome: String
                var delivered = ContinuousClock.now
                if text.isEmpty {
                    outcome = "nothing heard"
                    indicator.flash(.nothingHeard)
                } else if dryRun {
                    outcome = "dry run"
                    indicator.hide()
                    Log.dictation.notice("Dry-run \(style.name, privacy: .public) text: \(text, privacy: .public)")
                } else {
                    lastText = text
                    indicator.hide()
                    let result = await paster.deliver(text) { delivered = .now }
                    outcome = result.rawValue
                    onDelivered?(UsageStats.wordCount(transcript), audioSeconds)
                    // Push-to-talk never makes a note of its own (it can go to the daily note or a file instead).
                    if savesQuickDictations, !indicator.isPushToTalk {
                        onQuickNote?(QuickCapture(text: text, transcript: transcript, style: style, language: language, recorded: recorded, duration: audioSeconds))
                    }
                    if let fallbackNote {
                        indicator.showError(DictationIssue.rewriteFallback(fallbackNote).message)
                    } else if result != .pasted {
                        indicator.flash(.clipboard, seconds: 3)
                    }
                }
                // Push-to-talk also adds its text to the daily note or a file when chosen on the pill.
                if !text.isEmpty, indicator.isPushToTalk, let destination = indicator.pushDestination {
                    onPushToTalkText?(text, destination, recorded)
                }
                if !text.isEmpty, remembersStyle { onStyleUsed?(style, targetApp) }
                if !text.isEmpty { onLanguageUsed?(language, targetApp) }
                if text.isEmpty || dryRun { delivered = .now }
                lastReport = DictationReport(
                    finishedAt: Date(),
                    styleName: style.displayName,
                    audioSeconds: audioSeconds,
                    stopToText: textReady - stoppedAt,
                    stopToDelivery: delivered - stoppedAt,
                    rewriteDuration: rewriteDuration,
                    outcome: outcome,
                    passes: await streamer.passCount,
                    characters: text.count,
                    preview: String(text.prefix(600))
                )
                lastIssue = dryRun ? nil : fallbackNote.map(DictationIssue.rewriteFallback)
                Log.dictation.notice("Dictation \(outcome, privacy: .public) [\(style.name, privacy: .public)]: \(audioSeconds, format: .fixed(precision: 1))s audio, stop→text \(textReady - stoppedAt, privacy: .public), rewrite \(rewriteDuration.map { "\($0)" } ?? "–", privacy: .public), stop→paste \(delivered - stoppedAt, privacy: .public)")
            } catch {
                if generation == self.generation {
                    fail(.transcription(error.localizedDescription))
                }
            }
            if generation == self.generation {
                phase = .idle
                self.streamer = nil
                indicator.currentStyle = nil
            }
        }
    }

    #if DEBUG
    /// Dry runs keep their audio, raw 16 kHz float samples, to replay through a model outside the app.
    private static func saveDebugRecording(_ samples: [Float]) {
        let url = ModelLocations.root.deletingLastPathComponent().appending(path: "Debug/last-dictation.f32")
        try? samples.withUnsafeBytes { Data($0) }.write(to: url)
    }
    #endif

    /// Long recording: no paste. Finish the transcript, hand the recording off, and say so.
    private func finishLongForm(streamer: StreamingTranscriber, audioSeconds: Double, recorded: Date, generation: Int) {
        let samples = recorder.samples.samples(from: 0)
        let style = self.style
        let language = self.language
        let targetApp = self.targetApp
        let meeting = deliveryOverride == .meeting
        let speakers = speakerCount
        let dailyNote = indicator.dailyNote
        finishTask = Task {
            do {
                let engine = self.engine()
                if !(await engine.isLoaded) {
                    indicator.show(.preparingModel(firstTime: engine.needsFirstTimePreparation))
                    try await waitForModel()
                }
                let transcript = try await streamer.finish()
                guard generation == self.generation else { return }
                if !TranscriptCleaner.hasSpeech(transcript) {
                    // Nothing to summarise: a stray "." must not become a note written by the model.
                    indicator.flash(.nothingHeard)
                } else if dryRun {
                    Log.dictation.notice("Dry-run long-form [\(style.name, privacy: .public)]: \(transcript.count) characters")
                    onLongForm?(LongFormCapture(transcript: transcript, samples: samples, style: style, language: language, recorded: recorded, duration: audioSeconds, meeting: meeting, speakers: speakers, dailyNote: dailyNote))
                    indicator.flash(.notice(String(localized: "Long recording: making a note")), seconds: 2.5)
                } else {
                    onLongForm?(LongFormCapture(transcript: transcript, samples: samples, style: style, language: language, recorded: recorded, duration: audioSeconds, meeting: meeting, speakers: speakers, dailyNote: dailyNote))
                    indicator.flash(.notice(String(localized: "Long recording: making a note")), seconds: 2.5)
                }
                if TranscriptCleaner.hasSpeech(transcript) { onLanguageUsed?(language, targetApp) }
                Log.dictation.notice("Long-form recording handed off: \(audioSeconds, format: .fixed(precision: 0))s")
            } catch {
                if generation == self.generation { fail(.transcription(error.localizedDescription)) }
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

    func dismissIssue() { lastIssue = nil }

    private func fail(_ issue: DictationIssue) {
        let message = issue.message
        indicator.currentStyle = nil
        recorder.stop()
        streamer = nil
        phase = .idle
        lastIssue = issue
        cues.play(.cancel)
        indicator.showError(message)
        Log.dictation.error("\(message, privacy: .public)")
    }
}
