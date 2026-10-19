import APCore
import Foundation

/// Contents of the shared settings file in the vault (PRD "Configuration"): what all devices share,
/// plus one section per device. Keys are snake_case and enum values kebab-case for hand editing.
public struct SharedConfig: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var vocabulary: [String] = []
    /// Master tag list (used from milestone 5).
    public var tags: [String] = []
    public var styles: [ConfigStyle] = []
    /// Keyed by device name, e.g. "Wes's MacBook Air".
    public var devices: [String: DeviceSection] = [:]

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        vocabulary = try c.decodeIfPresent([String].self, forKey: .vocabulary) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        styles = try c.decodeIfPresent([ConfigStyle].self, forKey: .styles) ?? []
        devices = try c.decodeIfPresent([String: DeviceSection].self, forKey: .devices) ?? [:]
    }
}

public struct ConfigStyle: Codable, Equatable, Sendable {
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
    public var returnStops: Bool = true
    public var holdForRaw: Bool = true
    public var fallbackShortcut: Bool = true
    public var doubleTapWindow: Double = 0.4
    public var warmMicOnFirstTap: Bool = true
    public var transcriptionModel: String = DictationSettings().transcriptionModel
    public var writingModel: String = DictationSettings().writingModel
    public var pickStyleAfterStop: Bool = false
    public var pickerAutoConfirm: Double = 1.0

    enum CodingKeys: String, CodingKey {
        case microphones, stop
        case returnStops = "return_stops", holdForRaw = "hold_for_raw", fallbackShortcut = "fallback_shortcut"
        case doubleTapWindow = "double_tap_window", warmMicOnFirstTap = "warm_mic_on_first_tap"
        case transcriptionModel = "transcription_model", writingModel = "writing_model"
        case pickStyleAfterStop = "pick_style_after_stop", pickerAutoConfirm = "picker_auto_confirm"
    }

    public init() {}

    public init(_ settings: DictationSettings) {
        microphones = settings.preferredMicrophones.map { Microphone(name: $0.name, uid: $0.uid) }
        stop = ConfigStyle.kebab(settings.stopGesture.rawValue)
        returnStops = settings.returnStops
        holdForRaw = settings.holdFnForRaw
        fallbackShortcut = settings.fallbackShortcutEnabled
        doubleTapWindow = settings.doubleTapWindow
        warmMicOnFirstTap = settings.warmMicOnFirstTap
        transcriptionModel = settings.transcriptionModel
        writingModel = settings.writingModel
        pickStyleAfterStop = settings.pickStyleAfterStop
        pickerAutoConfirm = settings.pickerAutoConfirm
    }

    public init(from decoder: any Decoder) throws {
        let defaults = DeviceSection()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        microphones = try c.decodeIfPresent([Microphone].self, forKey: .microphones) ?? []
        stop = try c.decodeIfPresent(String.self, forKey: .stop) ?? defaults.stop
        returnStops = try c.decodeIfPresent(Bool.self, forKey: .returnStops) ?? defaults.returnStops
        holdForRaw = try c.decodeIfPresent(Bool.self, forKey: .holdForRaw) ?? defaults.holdForRaw
        fallbackShortcut = try c.decodeIfPresent(Bool.self, forKey: .fallbackShortcut) ?? defaults.fallbackShortcut
        doubleTapWindow = try c.decodeIfPresent(Double.self, forKey: .doubleTapWindow) ?? defaults.doubleTapWindow
        warmMicOnFirstTap = try c.decodeIfPresent(Bool.self, forKey: .warmMicOnFirstTap) ?? defaults.warmMicOnFirstTap
        transcriptionModel = try c.decodeIfPresent(String.self, forKey: .transcriptionModel) ?? defaults.transcriptionModel
        writingModel = try c.decodeIfPresent(String.self, forKey: .writingModel) ?? defaults.writingModel
        pickStyleAfterStop = try c.decodeIfPresent(Bool.self, forKey: .pickStyleAfterStop) ?? defaults.pickStyleAfterStop
        pickerAutoConfirm = try c.decodeIfPresent(Double.self, forKey: .pickerAutoConfirm) ?? defaults.pickerAutoConfirm
    }

    /// Writes this section's values into the app's settings, leaving local-only fields alone.
    public func apply(to settings: inout DictationSettings) {
        settings.preferredMicrophones = microphones.map { MicrophonePreference(uid: $0.uid, name: $0.name) }
        settings.stopGesture = StopGesture(rawValue: ConfigStyle.camel(stop)) ?? settings.stopGesture
        settings.returnStops = returnStops
        settings.holdFnForRaw = holdForRaw
        settings.fallbackShortcutEnabled = fallbackShortcut
        settings.doubleTapWindow = min(max(doubleTapWindow, 0.2), 0.8)
        settings.warmMicOnFirstTap = warmMicOnFirstTap
        settings.transcriptionModel = transcriptionModel
        settings.writingModel = writingModel
        settings.pickStyleAfterStop = pickStyleAfterStop
        settings.pickerAutoConfirm = min(max(pickerAutoConfirm, 0.25), 5)
    }
}
