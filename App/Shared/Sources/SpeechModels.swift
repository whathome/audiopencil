import APCore
import APModels
import APTranscription
import Foundation

/// Which Whisper model a recording uses, on either platform.
enum SpeechModels {
    /// Prepares in about 90 s on an M1: other languages work quickly while the better model prepares.
    static let starter = "openai_whisper-small"

    /// The multilingual model to end up with: the one in Settings, unless it's too big for this Mac.
    static func multilingualTarget(_ settings: DictationSettings, machine: MachineProfile = .current) -> String {
        let chosen = settings.multilingualTranscriptionModel
        if let megabytes = TranscriptionModelOption.option(for: chosen)?.approximateDownloadMB,
           UInt64(megabytes) * 1_000_000 > machine.transcriptionModelBudget {
            return starter
        }
        return chosen
    }

    /// The Whisper model a recording in `language` uses: English as configured; other languages use the
    /// multilingual model once it's prepared for this Mac, and the quicker starter model until then.
    static func bestVariant(for language: SpokenLanguage, settings: DictationSettings) -> String {
        let configured = settings.transcriptionVariant(for: language)
        guard !language.isEnglish, configured == settings.multilingualTranscriptionModel else { return configured }
        let target = multilingualTarget(settings)
        return WhisperEngine(variant: target).isReady ? target : starter
    }
}
