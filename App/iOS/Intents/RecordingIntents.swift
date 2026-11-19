import ActivityKit
import AppIntents
import Foundation

/// The Lock Screen and Dynamic Island view of a recording. Shows only the clock and state, never the words.
struct RecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the clock would read 0:00 if there had been no pauses (now minus recorded time).
        var clockStart: Date
        /// Set while paused: the clock stops here.
        var pausedAt: Date?
        /// Two-letter language badge, e.g. "EN".
        var language: String
        /// A short reason when something needs attention, e.g. "AirPods disconnected".
        var notice: String?

        var isPaused: Bool { pausedAt != nil }
    }
}

/// What the intents call into. The app sets it at launch; the widget extension compiles the intents for
/// its buttons but never runs them (these intents run in the app's process).
@MainActor
protocol RecordingControlling: AnyObject {
    var isRecording: Bool { get }
    func startRecordingFromIntent() async throws
    func pauseRecording()
    func resumeRecording()
    func stopRecordingFromIntent() async
}

@MainActor
enum RecordingControl {
    static weak var handler: (any RecordingControlling)?
}

/// Starts a recording, from Siri, Shortcuts or the Action Button. Recording can start in the background
/// because this is an audio recording intent; the recording shows a Live Activity throughout.
struct StartRecordingIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Start Recording"
    static let description = IntentDescription("Starts recording a note in Audio Pencil.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try await RecordingControl.handler?.startRecordingFromIntent()
        return .result()
    }
}

/// Starts a recording, or stops the one that's running: one control for Control Centre and the Action Button.
struct ToggleRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Record or Stop"
    static let description = IntentDescription("Starts recording a note in Audio Pencil, or stops and saves the recording that's running.")

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let handler = RecordingControl.handler else { return .result() }
        if handler.isRecording {
            await handler.stopRecordingFromIntent()
        } else {
            try await handler.startRecordingFromIntent()
        }
        return .result()
    }
}

struct PauseRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Recording"
    static let description = IntentDescription("Pauses the recording; resume it to carry on in the same note.")

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingControl.handler?.pauseRecording()
        return .result()
    }
}

struct ResumeRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Recording"
    static let description = IntentDescription("Carries on a paused recording.")

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingControl.handler?.resumeRecording()
        return .result()
    }
}

struct StopRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let description = IntentDescription("Stops the recording and makes it a note in your last style.")

    @MainActor
    func perform() async throws -> some IntentResult {
        await RecordingControl.handler?.stopRecordingFromIntent()
        return .result()
    }
}
