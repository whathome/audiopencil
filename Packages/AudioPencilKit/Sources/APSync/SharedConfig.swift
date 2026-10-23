import APCore
import Foundation

/// Contents of the shared settings file in the vault (PRD "Configuration"): what all devices share,
/// plus one section per device. Keys are snake_case and enum values kebab-case for hand editing.
public struct SharedConfig: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case version, vocabulary, tags, styles, devices
        case writingSamples = "writing_samples"
        case expireRegularAudio = "expire_regular_audio_after_a_year"
        case languageVocabulary = "vocabulary_by_language"
        case taskKeywords = "task_keywords"
    }

    public var version: Int = 1
    public var vocabulary: [String] = []
    /// Extra vocabulary for one language only, keyed by Whisper code ("fr"). Added to `vocabulary`.
    public var languageVocabulary: [String: [String]] = [:]
    /// Master tag list (used from milestone 5).
    public var tags: [String] = []
    /// Dictations starting with one of these become an Obsidian task ("new task …" → "- [ ] …").
    public var taskKeywords: [String] = TaskKeywords.defaults
    public var styles: [ConfigStyle] = []
    /// The user's writing, for the "Like me" style.
    public var writingSamples: [WritingSample] = []
    /// Retention board: remove the audio of "regular" notes a year after recording (vault-wide policy).
    public var expireRegularAudio: Bool = true
    /// Keyed by device name, e.g. "Wes's MacBook Air".
    public var devices: [String: DeviceSection] = [:]

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        vocabulary = try c.decodeIfPresent([String].self, forKey: .vocabulary) ?? []
        languageVocabulary = try c.decodeIfPresent([String: [String]].self, forKey: .languageVocabulary) ?? [:]
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        taskKeywords = try c.decodeIfPresent([String].self, forKey: .taskKeywords) ?? TaskKeywords.defaults
        styles = try c.decodeIfPresent([ConfigStyle].self, forKey: .styles) ?? []
        writingSamples = try c.decodeIfPresent([WritingSample].self, forKey: .writingSamples) ?? []
        expireRegularAudio = try c.decodeIfPresent(Bool.self, forKey: .expireRegularAudio) ?? true
        devices = try c.decodeIfPresent([String: DeviceSection].self, forKey: .devices) ?? [:]
    }
}

public struct ConfigStyle: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var shortcut: Int?
    public var enabled: Bool
    public var raw: Bool
    public var instructions: String
    public var intensity: String
    public var tone: String
    public var length: String
    public var mode: String
    public var suggestTags: Bool
    public var actionItems: Bool
    public var keepAudio: Bool
    public var folder: String?

    enum CodingKeys: String, CodingKey {
        case id, name, shortcut, enabled, raw, instructions, intensity, tone, length, mode
        case suggestTags = "suggest_tags", actionItems = "action_items", keepAudio = "keep_audio", folder
    }

    public init(_ style: Style) {
        id = style.id
        name = style.name
        shortcut = style.shortcut
        enabled = style.isEnabled
        raw = style.isRaw
        instructions = style.instructions
        intensity = style.intensity.rawValue
        tone = Self.kebab(style.tone.rawValue)
        length = Self.kebab(style.length.rawValue)
        mode = Self.kebab(style.mode.rawValue)
        suggestTags = style.suggestTags
        actionItems = style.extractActionItems
        keepAudio = style.keepAudio
        folder = style.folder
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        shortcut = try c.decodeIfPresent(Int.self, forKey: .shortcut)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        raw = try c.decodeIfPresent(Bool.self, forKey: .raw) ?? false
        instructions = try c.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        intensity = try c.decodeIfPresent(String.self, forKey: .intensity) ?? "moderate"
        tone = try c.decodeIfPresent(String.self, forKey: .tone) ?? "as-spoken"
        length = try c.decodeIfPresent(String.self, forKey: .length) ?? "as-spoken"
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "both"
        suggestTags = try c.decodeIfPresent(Bool.self, forKey: .suggestTags) ?? false
        actionItems = try c.decodeIfPresent(Bool.self, forKey: .actionItems) ?? false
        keepAudio = try c.decodeIfPresent(Bool.self, forKey: .keepAudio) ?? false
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
    }

    /// Back to the app's model. Unknown enum values fall back to defaults rather than failing.
    public var style: Style {
        Style(
            id: id, name: name, shortcut: shortcut, isRaw: raw, instructions: instructions,
            intensity: Style.Intensity(rawValue: intensity) ?? .moderate,
            tone: Style.Tone(rawValue: Self.camel(tone)) ?? .asSpoken,
            length: Style.Length(rawValue: Self.camel(length)) ?? .asSpoken,
            suggestTags: suggestTags, extractActionItems: actionItems,
            mode: Style.Mode(rawValue: Self.camel(mode)) ?? .both,
            keepAudio: keepAudio, folder: folder, isEnabled: enabled
        )
    }

    /// "asSpoken" → "as-spoken"
    static func kebab(_ value: String) -> String {
        value.reduce(into: "") { result, character in
            if character.isUppercase { result += "-" + character.lowercased() } else { result.append(character) }
        }
    }

    /// "as-spoken" → "asSpoken"
    static func camel(_ value: String) -> String {
        let parts = value.split(separator: "-")
        return (parts.first.map(String.init) ?? "") + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }
}

/// Settings that belong to one device (PRD: mic priority, hotkey, …).
public struct DeviceSection: Codable, Equatable, Sendable {
    public struct Microphone: Codable, Equatable, Sendable {
        public var name: String
        public var uid: String
    }

    public var microphones: [Microphone] = []
    public var stop: String = "single-tap-fn"
    public var key: String = "fn"
    public var start: String = "double-tap"
    /// e.g. "ctrl+opt+49": modifiers, then the virtual key code.
    public var shortcut: String = "ctrl+opt+49"
    public var returnStops: Bool = true
    public var holdForRaw: Bool = true
    public var pushToTalkDelay: Double = DictationSettings().pushToTalkDelay
    public var fallbackShortcut: Bool = true
    public var doubleTapWindow: Double = 0.4
    public var warmMicOnFirstTap: Bool = true
    public var transcriptionModel: String = DictationSettings().transcriptionModel
    public var multilingualModel: String = DictationSettings().multilingualTranscriptionModel
    /// Dictation languages offered on this device (Whisper codes). Empty: English plus the Mac's languages.
    public var languages: [String] = []
    public var writingModel: String = DictationSettings().writingModel
    public var pickStyleAfterStop: Bool = false
    public var pickerAutoConfirm: Double = 1.0
    public var longFormThreshold: Double = 300
    public var saveQuickDictations: Bool = false
    public var keepClipboard: Bool = true
    public var sounds: String = "tricorder"
    public var soundVolume: Double = 0.35

    enum CodingKeys: String, CodingKey {
        case microphones, stop, key, start, shortcut
        case returnStops = "return_stops", holdForRaw = "hold_for_raw", fallbackShortcut = "fallback_shortcut"
        case pushToTalkDelay = "push_to_talk_delay"
        case doubleTapWindow = "double_tap_window", warmMicOnFirstTap = "warm_mic_on_first_tap"
        case transcriptionModel = "transcription_model", writingModel = "writing_model"
        case multilingualModel = "multilingual_transcription_model", languages
        case pickStyleAfterStop = "pick_style_after_stop", pickerAutoConfirm = "picker_auto_confirm"
        case longFormThreshold = "long_form_threshold_seconds", saveQuickDictations = "save_quick_dictations", keepClipboard = "keep_clipboard"
        case sounds, soundVolume = "sound_volume"
    }

    public init() {}

    public init(_ settings: DictationSettings) {
        microphones = settings.preferredMicrophones.map { Microphone(name: $0.name, uid: $0.uid) }
        stop = ConfigStyle.kebab(settings.stopGesture.rawValue)
        key = ConfigStyle.kebab(settings.gestureKey.rawValue)
        start = ConfigStyle.kebab(settings.startGesture.rawValue)
        shortcut = Self.encode(settings.fallbackShortcut)
        returnStops = settings.returnStops
        holdForRaw = settings.holdFnForRaw
        pushToTalkDelay = settings.pushToTalkDelay
        fallbackShortcut = settings.fallbackShortcutEnabled
        doubleTapWindow = settings.doubleTapWindow
        warmMicOnFirstTap = settings.warmMicOnFirstTap
        transcriptionModel = settings.transcriptionModel
        multilingualModel = settings.multilingualTranscriptionModel
        languages = settings.dictationLanguages
        writingModel = settings.writingModel
        pickStyleAfterStop = settings.pickStyleAfterStop
        pickerAutoConfirm = settings.pickerAutoConfirm
        longFormThreshold = settings.longFormThreshold
        saveQuickDictations = settings.saveQuickDictations
        keepClipboard = settings.keepClipboard
        sounds = settings.cueTheme
        soundVolume = settings.cueVolume
    }

    public init(from decoder: any Decoder) throws {
        let defaults = DeviceSection()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        microphones = try c.decodeIfPresent([Microphone].self, forKey: .microphones) ?? []
        stop = try c.decodeIfPresent(String.self, forKey: .stop) ?? defaults.stop
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? defaults.key
        start = try c.decodeIfPresent(String.self, forKey: .start) ?? defaults.start
        shortcut = try c.decodeIfPresent(String.self, forKey: .shortcut) ?? defaults.shortcut
        returnStops = try c.decodeIfPresent(Bool.self, forKey: .returnStops) ?? defaults.returnStops
        holdForRaw = try c.decodeIfPresent(Bool.self, forKey: .holdForRaw) ?? defaults.holdForRaw
        pushToTalkDelay = try c.decodeIfPresent(Double.self, forKey: .pushToTalkDelay) ?? defaults.pushToTalkDelay
        guard pushToTalkDelay.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .pushToTalkDelay, in: c, debugDescription: "push_to_talk_delay must be a finite number of seconds")
        }
        fallbackShortcut = try c.decodeIfPresent(Bool.self, forKey: .fallbackShortcut) ?? defaults.fallbackShortcut
        doubleTapWindow = try c.decodeIfPresent(Double.self, forKey: .doubleTapWindow) ?? defaults.doubleTapWindow
        warmMicOnFirstTap = try c.decodeIfPresent(Bool.self, forKey: .warmMicOnFirstTap) ?? defaults.warmMicOnFirstTap
        transcriptionModel = try c.decodeIfPresent(String.self, forKey: .transcriptionModel) ?? defaults.transcriptionModel
        multilingualModel = try c.decodeIfPresent(String.self, forKey: .multilingualModel) ?? defaults.multilingualModel
        languages = try c.decodeIfPresent([String].self, forKey: .languages) ?? defaults.languages
        writingModel = try c.decodeIfPresent(String.self, forKey: .writingModel) ?? defaults.writingModel
        pickStyleAfterStop = try c.decodeIfPresent(Bool.self, forKey: .pickStyleAfterStop) ?? defaults.pickStyleAfterStop
        pickerAutoConfirm = try c.decodeIfPresent(Double.self, forKey: .pickerAutoConfirm) ?? defaults.pickerAutoConfirm
        longFormThreshold = try c.decodeIfPresent(Double.self, forKey: .longFormThreshold) ?? defaults.longFormThreshold
        saveQuickDictations = try c.decodeIfPresent(Bool.self, forKey: .saveQuickDictations) ?? defaults.saveQuickDictations
        keepClipboard = try c.decodeIfPresent(Bool.self, forKey: .keepClipboard) ?? defaults.keepClipboard
        sounds = try c.decodeIfPresent(String.self, forKey: .sounds) ?? defaults.sounds
        soundVolume = try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? defaults.soundVolume
    }

    static func encode(_ shortcut: KeyShortcut) -> String {
        var parts: [String] = []
        if shortcut.modifiers & KeyShortcut.control != 0 { parts.append("ctrl") }
        if shortcut.modifiers & KeyShortcut.option != 0 { parts.append("opt") }
        if shortcut.modifiers & KeyShortcut.shift != 0 { parts.append("shift") }
        if shortcut.modifiers & KeyShortcut.command != 0 { parts.append("cmd") }
        return (parts + ["\(shortcut.keyCode)"]).joined(separator: "+")
    }

    static func decode(_ text: String) -> KeyShortcut? {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, let code = Int(last), (0..<128).contains(code) else { return nil }
        var modifiers: UInt64 = 0
        for part in parts.dropLast() {
            switch part {
            case "ctrl", "control": modifiers |= KeyShortcut.control
            case "opt", "option", "alt": modifiers |= KeyShortcut.option
            case "shift": modifiers |= KeyShortcut.shift
            case "cmd", "command": modifiers |= KeyShortcut.command
            default: return nil
            }
        }
        return KeyShortcut(keyCode: code, modifiers: modifiers)
    }

    /// Writes this section's values into the app's settings, leaving local-only fields alone.
    public func apply(to settings: inout DictationSettings) {
        settings.preferredMicrophones = microphones.map { MicrophonePreference(uid: $0.uid, name: $0.name) }
        settings.stopGesture = StopGesture(rawValue: ConfigStyle.camel(stop)) ?? settings.stopGesture
        settings.gestureKey = GestureKey(rawValue: ConfigStyle.camel(key)) ?? settings.gestureKey
        settings.startGesture = StartGesture(rawValue: ConfigStyle.camel(start)) ?? settings.startGesture
        settings.fallbackShortcut = Self.decode(shortcut) ?? settings.fallbackShortcut
        settings.returnStops = returnStops
        settings.holdFnForRaw = holdForRaw
        settings.pushToTalkDelay = min(max(pushToTalkDelay, DictationSettings.pushToTalkDelayRange.lowerBound), DictationSettings.pushToTalkDelayRange.upperBound)
        settings.fallbackShortcutEnabled = fallbackShortcut
        settings.doubleTapWindow = min(max(doubleTapWindow, 0.2), 0.8)
        settings.warmMicOnFirstTap = warmMicOnFirstTap
        settings.transcriptionModel = transcriptionModel
        // An English-only model can't be the multilingual one; keep the local choice instead.
        if !DictationSettings.isEnglishOnly(multilingualModel) { settings.multilingualTranscriptionModel = multilingualModel }
        settings.dictationLanguages = languages.map { $0.lowercased() }.filter(SpokenLanguage.whisperCodes.contains)
        settings.writingModel = writingModel
        settings.pickStyleAfterStop = pickStyleAfterStop
        settings.pickerAutoConfirm = min(max(pickerAutoConfirm, 0.25), 5)
        settings.longFormThreshold = min(max(longFormThreshold, 60), 3_600)
        settings.saveQuickDictations = saveQuickDictations
        settings.keepClipboard = keepClipboard
        settings.cueTheme = sounds
        settings.cueVolume = min(max(soundVolume, 0), 1)
    }
}
