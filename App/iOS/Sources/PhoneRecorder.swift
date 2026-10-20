import APAudio
import APCore
import APTranscription
import AVFoundation
import Foundation
import Observation

/// A finished recording, waiting for its style.
struct PhoneCapture: Identifiable {
    let id = UUID()
    var transcript: String
    var samples: [Float]
    var language: SpokenLanguage
    var recorded: Date
    var duration: TimeInterval
}

/// One recording at a time: the microphone, the live transcript, pause and resume, and stopping into a
/// capture. Every iPhone recording becomes a note (there's no field to paste into).
@Observable
final class PhoneRecorder {
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
    /// Recorded time, not counting pauses.
    private(set) var accumulated: TimeInterval = 0
    /// When the current stretch of recording began (nil while paused or idle).
    private(set) var stretchStartedAt: Date?

    @ObservationIgnored private unowned let app: PhoneModel
    @ObservationIgnored private let audio = AudioRecorder()
    @ObservationIgnored private var streamer: StreamingTranscriber?
    @ObservationIgnored private var recordedAt = Date()

    init(app: PhoneModel) {
        self.app = app
    }

    func elapsed(at date: Date = .now) -> TimeInterval {
        accumulated + (stretchStartedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    var isActive: Bool { phase != .idle }

    func start() async {
        guard phase == .idle else { return }
        lastError = nil
        phase = .starting
        guard await AVAudioApplication.requestRecordPermission() else {
            lastError = String(localized: "Audio Pencil needs the microphone. Allow it in Settings › Privacy & Security › Microphone.")
            phase = .idle
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetoothHFP, .defaultToSpeaker])
            try session.setActive(true)
            language = app.currentLanguage
            app.useLanguage(language) // picks this language's model and starts loading it
            try await audio.beginRecording(
                deviceID: nil,
                onLevel: { [weak self] value in Task { @MainActor in self?.level = value } },
                onInterruption: { [weak self] in Task { @MainActor in self?.pause() } }
            )
        } catch {
            lastError = String(localized: "Couldn't start the microphone: \(error.localizedDescription)")
            phase = .idle
            return
        }
        recordedAt = Date()
        accumulated = 0
        stretchStartedAt = Date()
        liveText = ""
        phase = .recording
        let streamer = makeStreamer()
        self.streamer = streamer
        await streamer.start()
        Log.dictation.notice("iPhone recording started in \(self.language.code, privacy: .public)")
    }

    func pause() {
        guard phase == .recording else { return }
        audio.setPaused(true)
        accumulated = elapsed()
        stretchStartedAt = nil
        level = 0
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        audio.setPaused(false)
        stretchStartedAt = Date()
        phase = .recording
    }

    /// Another language for this recording: what's been said so far is transcribed again in it.
    func select(_ language: SpokenLanguage) {
        guard language != self.language else { return }
        self.language = language
        app.useLanguage(language)
        guard phase == .recording || phase == .paused, let old = streamer else { return }
        let streamer = makeStreamer()
        self.streamer = streamer
        Task {
            await old.cancel()
            await streamer.start()
        }
    }

    /// Stops and finishes the transcript. Nil when nothing was said.
    func stop() async -> PhoneCapture? {
        guard phase == .recording || phase == .paused, let streamer else { return nil }
        let duration = elapsed()
        accumulated = duration
        stretchStartedAt = nil
        phase = .finishing
        let samples = audio.samples.samples(from: 0)
        audio.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        defer {
            phase = .idle
            self.streamer = nil
            level = 0
        }
        do {
            try await app.waitForModel()
            let transcript = try await streamer.finish()
            guard TranscriptCleaner.hasSpeech(transcript) else {
                lastError = String(localized: "Nothing heard.")
                return nil
            }
            Log.dictation.notice("iPhone recording finished: \(duration, format: .fixed(precision: 0)) s")
            return PhoneCapture(transcript: transcript, samples: samples, language: language, recorded: recordedAt, duration: duration)
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        stretchStartedAt = nil
        accumulated = 0
        liveText = ""
        level = 0
        phase = .idle
    }

    private func makeStreamer() -> StreamingTranscriber {
        let engine = app.whisper
        return StreamingTranscriber(
            engine: engine,
            source: audio.samples,
            isEngineReady: { await engine.isLoaded },
            onUpdate: { [weak self] confirmed, pending in
                Task { @MainActor in self?.liveText = [confirmed, pending].filter { !$0.isEmpty }.joined(separator: " ") }
            }
        )
    }
}
