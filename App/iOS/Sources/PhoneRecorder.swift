import APAudio
import APCore
import APTranscription
import AVFoundation
import Foundation
import Observation
import UIKit
import UserNotifications

/// A finished recording, waiting for its style.
struct PhoneCapture: Identifiable {
    let id = UUID()
    var transcript: String
    var samples: [Float]
    var language: SpokenLanguage
    var recorded: Date
    var duration: TimeInterval
    /// Meeting mode: label who spoke, `speakers` people if known.
    var meeting = false
    var speakers: Int?
    /// Link the note in that day's daily note.
    var dailyNote = false
}

/// One recording at a time: the microphone, the live transcript, pause and resume, and stopping into a
/// capture. Keeps going with the phone locked (background audio), shows a Live Activity, and can be driven
/// from the Lock Screen, Control Centre, the Action Button, Siri and Shortcuts.
@Observable
final class PhoneRecorder: RecordingControlling {
    enum Phase: Equatable {
        case idle
        case starting
        case recording
        case paused
        case finishing
    }

    private(set) var phase: Phase = .idle
    /// What's been heard so far, confirmed and still settling.
    private(set) var liveText = ""
    /// 0…1 loudness, for the level meter.
    private(set) var level: Float = 0
    private(set) var language: SpokenLanguage = .english
    private(set) var lastError: String?
    /// Why the recording is paused, when it wasn't the user (e.g. "AirPods disconnected").
    private(set) var pauseReason: String?
    /// Meeting mode for this recording (set before or during it): speakers labelled in the note.
    /// Back to one speaker after each recording, the default.
    var meeting = false
    /// How many people are talking, if known; nil works it out.
    var speakerCount: Int?
    /// Daily-note link for this recording, if changed from the setting; back to the setting after each one.
    var dailyNoteOverride: Bool?

    /// Whether this recording's note will be linked in the daily note.
    var linksDailyNote: Bool {
        app.sync.dailyNotes == .on && (dailyNoteOverride ?? app.settings.dailyNoteLinks)
    }
    /// Recorded time, not counting pauses.
    private(set) var accumulated: TimeInterval = 0
    /// When the current stretch of recording began (nil while paused or idle).
    private(set) var stretchStartedAt: Date?

    @ObservationIgnored private unowned let app: PhoneModel
    @ObservationIgnored private let audio = AudioRecorder()
    @ObservationIgnored private let feedback = RecordingFeedback()
    @ObservationIgnored private let activity = RecordingActivity()
    @ObservationIgnored private var streamer: StreamingTranscriber?
    @ObservationIgnored private var recordedAt = Date()
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    /// Silence auto-stop: when words last arrived, and how much audio there was then.
    @ObservationIgnored private var lastWordsAt = Date()
    @ObservationIgnored private var lastWordsSample = 0
    @ObservationIgnored private var silenceWatch: Task<Void, Never>?

    init(app: PhoneModel) {
        self.app = app
    }

    func elapsed(at date: Date = .now) -> TimeInterval {
        accumulated + (stretchStartedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    var isActive: Bool { phase != .idle }

    // MARK: RecordingControlling (intents)

    var isRecording: Bool { phase == .starting || phase == .recording || phase == .paused }

    func startRecordingFromIntent() async throws {
        await start()
        if let lastError, phase == .idle { throw RecordingError.couldNotStart(lastError) }
    }

    func pauseRecording() { pause() }
    func resumeRecording() { resume() }

    /// Stopped away from the Record screen: no style sheet, so the note is written in the last style used.
    func stopRecordingFromIntent() async {
        guard let capture = await stop() else { return }
        app.notes.enqueue(capture, style: app.lastStyle)
    }

    enum RecordingError: LocalizedError {
        case couldNotStart(String)
        var errorDescription: String? {
            switch self { case .couldNotStart(let message): message }
        }
    }

    // MARK: Recording

    func start() async {
        guard phase == .idle else { return }
        lastError = nil
        pauseReason = nil
        phase = .starting
        // One model in memory at a time: a note being written waits until this recording is done.
        app.notes.pauseProcessing()
        guard await AVAudioApplication.requestRecordPermission() else {
            lastError = String(localized: "Audio Pencil needs the microphone. Allow it in Settings › Privacy & Security › Microphone.")
            phase = .idle
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .defaultToSpeaker])
            // Cues and haptics are muted during recording unless allowed.
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try session.setActive(true)
            language = app.currentLanguage
            app.useLanguage(language) // picks this language's model
            app.ensureModelLoading() // a recording started from the Lock Screen may be the app's first moment awake
            audio.setVoiceProcessing(app.reduceNoise)
            try await audio.beginRecording(
                deviceID: nil,
                onLevel: { [weak self] value in Task { @MainActor in self?.level = value } },
                onInterruption: { [weak self] in
                    Task { @MainActor in self?.pause(reason: String(localized: "The microphone stopped"), alert: true) }
                }
            )
        } catch {
            lastError = String(localized: "Couldn't start the microphone: \(error.localizedDescription)")
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            phase = .idle
            return
        }
        recordedAt = Date()
        accumulated = 0
        stretchStartedAt = Date()
        liveText = ""
        phase = .recording
        feedback.configure(theme: app.settings.cueTheme, volume: app.settings.cueVolume)
        audio.muteNext(seconds: 0.4) // keep the start cue out of the transcript
        feedback.started()
        activity.start(activityState())
        feedback.startHeartbeat(app.heartbeat, minutes: app.heartbeatMinutes)
        observeSession()
        startSilenceWatch()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let streamer = makeStreamer()
        self.streamer = streamer
        await streamer.start()
        Log.dictation.notice("iPhone recording started in \(self.language.code, privacy: .public) (app \(UIApplication.shared.applicationState == .active ? "on screen" : "in the background", privacy: .public))")
    }

    func pause() {
        pause(reason: nil, alert: false)
    }

    /// `reason` says why when it wasn't the user; `alert` also buzzes and lights the Lock Screen.
    private func pause(reason: String?, alert: Bool) {
        guard phase == .recording else { return }
        audio.setPaused(true)
        accumulated = elapsed()
        stretchStartedAt = nil
        level = 0
        pauseReason = reason
        phase = .paused
        feedback.stopHeartbeat()
        if alert {
            audio.muteNext(seconds: 0.6)
            feedback.alert()
            activity.update(activityState(), alert: (title: String(localized: "Recording paused"), body: reason ?? ""))
        } else {
            feedback.paused()
            activity.update(activityState())
        }
        Log.dictation.notice("iPhone recording paused\(reason.map { ": \($0)" } ?? "", privacy: .public)")
    }

    func resume() {
        guard phase == .paused else { return }
        pauseReason = nil
        audio.muteNext(seconds: 0.4)
        audio.setPaused(false)
        stretchStartedAt = Date()
        phase = .recording
        lastWordsAt = Date() // a pause isn't silence
        feedback.resumed()
        feedback.startHeartbeat(app.heartbeat, minutes: app.heartbeatMinutes)
        activity.update(activityState())
    }

    /// Another language for this recording: what's been said so far is transcribed again in it.
    func select(_ language: SpokenLanguage) {
        guard language != self.language else { return }
        self.language = language
        app.useLanguage(language)
        if phase == .recording || phase == .paused { activity.update(activityState()) }
        guard phase == .recording || phase == .paused, let old = streamer else { return }
        let streamer = makeStreamer()
        self.streamer = streamer
        Task {
            await old.cancel()
            await streamer.start()
        }
    }

    /// Stops and finishes the transcript. Nil when nothing was said. `keepingSamples` trims the audio
    /// (silence auto-stop drops the quiet tail).
    func stop(keepingSamples limit: Int? = nil) async -> PhoneCapture? {
        guard phase == .recording || phase == .paused, let streamer else { return nil }
        // The transcript and the audio file need a little time after the microphone (and with it the
        // background audio that keeps the app awake) is off.
        let background = UIApplication.shared.beginBackgroundTask(withName: "Finishing a recording")
        defer { UIApplication.shared.endBackgroundTask(background) }
        let duration = elapsed()
        accumulated = duration
        stretchStartedAt = nil
        phase = .finishing
        var samples = audio.samples.samples(from: 0)
        if let limit, limit < samples.count { samples = Array(samples.prefix(limit)) }
        feedback.stopped()
        feedback.stopHeartbeat()
        stopWatching()
        activity.end()
        try? await Task.sleep(for: .milliseconds(250)) // let the cue finish before the session goes
        audio.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let meeting = self.meeting
        let speakers = speakerCount
        let dailyNote = linksDailyNote
        defer {
            dailyNoteOverride = nil
            phase = .idle
            self.streamer = nil
            level = 0
            pauseReason = nil
            self.meeting = false
            speakerCount = nil
            app.notes.processQueue()
        }
        do {
            try await app.waitForModel()
            let transcript = try await streamer.finish()
            guard TranscriptCleaner.hasSpeech(transcript) else {
                lastError = String(localized: "Nothing heard.")
                Log.dictation.notice("iPhone recording had no speech; no note made")
                if UIApplication.shared.applicationState != .active {
                    PhoneNotes.notify(title: String(localized: "Nothing heard"), body: String(localized: "The recording had no speech in it, so no note was made."))
                }
                return nil
            }
            Log.dictation.notice("iPhone recording finished: \(duration, format: .fixed(precision: 0)) s")
            return PhoneCapture(
                transcript: transcript, samples: samples, language: language, recorded: recordedAt,
                duration: min(duration, Double(samples.count) / AudioRecorder.sampleRate), meeting: meeting, speakers: speakers,
                dailyNote: dailyNote
            )
        } catch {
            lastError = String(localized: "Transcription failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// After the note is made (or the recording discarded): a fresh screen for the next one.
    func clear() {
        guard phase == .idle else { return }
        liveText = ""
        accumulated = 0
        lastError = nil
    }

    func cancel() {
        guard isActive else { return }
        audio.stop()
        if let streamer { Task { await streamer.cancel() } }
        streamer = nil
        feedback.stopHeartbeat()
        stopWatching()
        activity.end()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        stretchStartedAt = nil
        accumulated = 0
        liveText = ""
        level = 0
        pauseReason = nil
        phase = .idle
        app.notes.processQueue()
    }

    // MARK: Live Activity

    private func activityState() -> RecordingAttributes.ContentState {
        let now = Date()
        return RecordingAttributes.ContentState(
            clockStart: now.addingTimeInterval(-elapsed(at: now)),
            pausedAt: phase == .paused ? now : nil,
            language: language.badge,
            notice: pauseReason
        )
    }

    // MARK: Microphone and interruptions

    private func observeSession() {
        stopObservingSession()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            let previous = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            MainActor.assumeIsolated { self?.routeChanged(reason, previous: previous) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            MainActor.assumeIsolated {
                // A call or an alarm took the microphone. Stay paused afterwards: carry on when you're ready.
                if type == .began { self?.pause(reason: String(localized: "Interrupted"), alert: false) }
            }
        })
    }

    /// AirPods (or another headset) went away: pause rather than carry on through the phone's own mic in a
    /// pocket, and say so with a distinct alert.
    private func routeChanged(_ reason: AVAudioSession.RouteChangeReason?, previous: AVAudioSessionRouteDescription?) {
        guard phase == .recording, reason == .oldDeviceUnavailable,
              let input = previous?.inputs.first, input.portType != .builtInMic
        else { return }
        pause(reason: String(localized: "\(input.portName) disconnected"), alert: true)
    }

    private func stopObservingSession() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    // MARK: Silence

    /// No new words for the chosen time (5 minutes at most): stop, drop the quiet tail, and make the note.
    private func startSilenceWatch() {
        lastWordsAt = Date()
        lastWordsSample = 0
        silenceWatch?.cancel()
        silenceWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled, phase == .recording else { continue }
                let limit = TimeInterval(app.autoStopMinutes * 60)
                if Date().timeIntervalSince(lastWordsAt) >= limit {
                    await autoStop()
                    return
                }
            }
        }
    }

    private func autoStop() async {
        let minutes = app.autoStopMinutes
        let tail = Int(1.5 * AudioRecorder.sampleRate)
        Log.dictation.notice("iPhone recording stopped after \(minutes) min without speech")
        guard let capture = await stop(keepingSamples: lastWordsSample + tail) else { return }
        let style = app.lastStyle
        app.notes.enqueue(capture, style: style)
        if UIApplication.shared.applicationState != .active {
            PhoneNotes.notify(
                title: String(localized: "Stopped after \(minutes) minutes of quiet"),
                body: String(localized: "The recording is saved. Open Audio Pencil to write it up as \(style.displayName).")
            )
        }
    }

    private func stopWatching() {
        silenceWatch?.cancel()
        silenceWatch = nil
        stopObservingSession()
    }

    private func heard(_ text: String) {
        let words = text.split(whereSeparator: \.isWhitespace).count
        if words > liveText.split(whereSeparator: \.isWhitespace).count {
            lastWordsAt = Date()
            lastWordsSample = audio.samples.count
        }
        liveText = text
    }

    private func makeStreamer() -> StreamingTranscriber {
        let engine = app.whisper
        return StreamingTranscriber(
            engine: engine,
            source: audio.samples,
            isEngineReady: { await engine.isLoaded },
            onUpdate: { [weak self] confirmed, pending in
                let text = [confirmed, pending].filter { !$0.isEmpty }.joined(separator: " ")
                Task { @MainActor in self?.heard(text) }
            }
        )
    }
}
