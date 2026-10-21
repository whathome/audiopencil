import APModels
import Foundation

/// The whole recording with word timings, for meeting mode's speaker labels.
public protocol TimedWordTranscribing: Sendable {
    func transcribeTimedWords(_ samples: [Float]) async throws -> [TimedWord]
}

/// What dictation needs from a speech model: `WhisperEngine`, or on the Mac `PhononEngine` (English only).
/// Residency is still owned by `ModelCoordinator`.
public protocol DictationEngine: ManagedModel, SpeechTranscribing, TimedWordTranscribing {
    /// The model's identifier, e.g. "openai_whisper-small.en".
    nonisolated var variant: String { get }
    /// True when the model files are on disk (no network needed to load).
    nonisolated var isDownloaded: Bool { get }
    /// True until the first successful load has compiled the model for this device.
    nonisolated var needsFirstTimePreparation: Bool { get }
    /// At stop, transcribe the whole recording in one pass instead of only the tail the live passes left.
    /// For models fast enough that one pass over minutes of audio takes about a second.
    nonisolated var transcribesWholeRecordingAtStop: Bool { get }
    var isLoaded: Bool { get async }
    /// `progress` receives 0…1.
    func download(progress: @escaping @Sendable (Double) -> Void) async throws
    /// Terms to spell correctly. Models without a prompt ignore them, so the app doesn't pick those when there are any.
    func setVocabulary(_ words: [String]) async
    /// Whisper code of the language to transcribe. English-only models ignore it.
    func setLanguage(_ code: String) async
    /// Called as each part of a first-time preparation starts, and with nil when it ends. Set before loading.
    func setPreparationHandler(_ handler: (@Sendable (ModelPreparation?) -> Void)?) async
}
