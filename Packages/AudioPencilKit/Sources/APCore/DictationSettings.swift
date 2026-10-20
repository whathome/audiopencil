import Foundation

/// How a running quick dictation is stopped with the Fn key.
public enum StopGesture: String, Codable, CaseIterable, Sendable {
    case singleTapFn
    case doubleTapFn

    public var label: String {
        switch self {
        case .singleTapFn: "Single tap Fn"
        case .doubleTapFn: "Double-tap Fn"
        }
    }
}

/// A microphone in the user's priority list. The name is kept so unplugged devices still show up.
public struct MicrophonePreference: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var uid: String
    public var name: String
    public var id: String { uid }

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

/// Per-device dictation preferences. Stored locally for now; moves into the shared
/// vault config file (per-device section) in milestone 4.
public struct DictationSettings: Codable, Equatable, Sendable {
    /// Gesture that stops a recording (starting is always a double-tap of Fn).
    public var stopGesture: StopGesture = .singleTapFn
    /// Press and hold Fn to talk; release to paste the raw transcript.
    public var holdFnForRaw: Bool = true
    /// Return / Enter also stops a recording (the key press is swallowed).
    public var returnStops: Bool = true
    /// ⌃⌥Space toggles recording, for keyboards without a usable Fn key.
    public var fallbackShortcutEnabled: Bool = true
    /// Maximum gap between the two taps of a double-tap, in seconds.
    public var doubleTapWindow: Double = 0.40
    /// WhisperKit model folder name used for English, e.g. "openai_whisper-small.en".
    public var transcriptionModel: String = "openai_whisper-small.en"
    /// WhisperKit model used for every other language. English-only (".en") models can't do this job.
    public var multilingualTranscriptionModel: String = "openai_whisper-large-v3-v20240930_turbo_632MB"
    /// Languages offered in the recording pill and Settings, in the user's order. Empty means the
    /// default: English plus the Mac's preferred languages.
    public var dictationLanguages: [String] = []
    /// Show the in-progress transcript under the indicator (debugging aid).
    public var showLiveText: Bool = false
    /// Preferred microphones, highest priority first. The first one connected is used;
    /// if none is, the system default input.
    public var preferredMicrophones: [MicrophonePreference] = []
    /// Turn the mic on at the first Fn tap so recording starts instantly on the second.
    /// The mic indicator briefly flashes on a lone Fn tap.
    public var warmMicOnFirstTap: Bool = true
    /// Names, places and terms Whisper should spell correctly, in every language.
    public var customVocabulary: [String] = []
    /// Extra terms for one language only, keyed by Whisper code.
    public var languageVocabulary: [String: [String]] = [:]
    /// Menu bar icon instead of a Dock icon.
    public var menuBarMode: Bool = false
    /// Hugging Face repository of the MLX writing model used for styles.
    public var writingModel: String = "mlx-community/SmolLM3-3B-4bit"
    /// Show a style picker after stopping (PRD flow) instead of delivering straight away.
    public var pickStyleAfterStop: Bool = false
    /// Seconds before the picker accepts the preselected style.
    public var pickerAutoConfirm: Double = 1.0
    /// Hotkey recordings longer than this become long-form notes (audio kept, review prompt) instead of pasting.
    public var longFormThreshold: Double = 300
    /// Also save quick dictations as notes in the vault (PRD default: paste and forget).
    public var saveQuickDictations: Bool = false
    /// Start/stop/cancel sound theme (a CueTheme raw value) and its volume (0…1).
    public var cueTheme: String = "tricorder"
    public var cueVolume: Double = 0.35

    public init() {}

    /// The languages to offer, never empty, always including `current`.
    public func offeredLanguages(including current: SpokenLanguage? = nil) -> [SpokenLanguage] {
        var codes = dictationLanguages.isEmpty ? SpokenLanguage.defaultCodes() : dictationLanguages
        if let current, !codes.contains(current.code) { codes.append(current.code) }
        return codes.map(SpokenLanguage.init)
    }

    /// The Whisper model that transcribes `language`: the English model for English (unless it's
    /// English-only and the language isn't), otherwise the multilingual one.
    public func transcriptionVariant(for language: SpokenLanguage) -> String {
        if language.isEnglish || !Self.isEnglishOnly(transcriptionModel) { return transcriptionModel }
        return multilingualTranscriptionModel
    }

    /// The global list plus `language`'s own list, without duplicates.
    public func vocabulary(for language: SpokenLanguage) -> [String] {
        var seen = Set<String>()
        return (customVocabulary + (languageVocabulary[language.code] ?? [])).filter { seen.insert($0).inserted }
    }

    /// ".en" Whisper variants and distil-whisper only know English.
    public static func isEnglishOnly(_ variant: String) -> Bool {
        variant.contains(".en") || variant.lowercased().contains("distil")
    }

    public init(from decoder: any Decoder) throws {
        // Decode leniently so adding fields never wipes existing preferences.
        let defaults = DictationSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stopGesture = try c.decodeIfPresent(StopGesture.self, forKey: .stopGesture) ?? defaults.stopGesture
        holdFnForRaw = try c.decodeIfPresent(Bool.self, forKey: .holdFnForRaw) ?? defaults.holdFnForRaw
        returnStops = try c.decodeIfPresent(Bool.self, forKey: .returnStops) ?? defaults.returnStops
        fallbackShortcutEnabled = try c.decodeIfPresent(Bool.self, forKey: .fallbackShortcutEnabled) ?? defaults.fallbackShortcutEnabled
        doubleTapWindow = try c.decodeIfPresent(Double.self, forKey: .doubleTapWindow) ?? defaults.doubleTapWindow
        transcriptionModel = try c.decodeIfPresent(String.self, forKey: .transcriptionModel) ?? defaults.transcriptionModel
        multilingualTranscriptionModel = try c.decodeIfPresent(String.self, forKey: .multilingualTranscriptionModel) ?? defaults.multilingualTranscriptionModel
        dictationLanguages = try c.decodeIfPresent([String].self, forKey: .dictationLanguages) ?? defaults.dictationLanguages
        showLiveText = try c.decodeIfPresent(Bool.self, forKey: .showLiveText) ?? defaults.showLiveText
        preferredMicrophones = try c.decodeIfPresent([MicrophonePreference].self, forKey: .preferredMicrophones) ?? defaults.preferredMicrophones
        warmMicOnFirstTap = try c.decodeIfPresent(Bool.self, forKey: .warmMicOnFirstTap) ?? defaults.warmMicOnFirstTap
        customVocabulary = try c.decodeIfPresent([String].self, forKey: .customVocabulary) ?? defaults.customVocabulary
        languageVocabulary = try c.decodeIfPresent([String: [String]].self, forKey: .languageVocabulary) ?? defaults.languageVocabulary
        menuBarMode = try c.decodeIfPresent(Bool.self, forKey: .menuBarMode) ?? defaults.menuBarMode
        writingModel = try c.decodeIfPresent(String.self, forKey: .writingModel) ?? defaults.writingModel
        pickStyleAfterStop = try c.decodeIfPresent(Bool.self, forKey: .pickStyleAfterStop) ?? defaults.pickStyleAfterStop
        pickerAutoConfirm = try c.decodeIfPresent(Double.self, forKey: .pickerAutoConfirm) ?? defaults.pickerAutoConfirm
        longFormThreshold = try c.decodeIfPresent(Double.self, forKey: .longFormThreshold) ?? defaults.longFormThreshold
        saveQuickDictations = try c.decodeIfPresent(Bool.self, forKey: .saveQuickDictations) ?? defaults.saveQuickDictations
        cueTheme = try c.decodeIfPresent(String.self, forKey: .cueTheme) ?? defaults.cueTheme
        cueVolume = try c.decodeIfPresent(Double.self, forKey: .cueVolume) ?? defaults.cueVolume
    }
}
