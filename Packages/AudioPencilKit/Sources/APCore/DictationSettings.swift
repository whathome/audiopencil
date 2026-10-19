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

/// Per-device dictation preferences. Stored locally for now; moves into the shared
/// vault config file (per-device section) in milestone 4.
public struct DictationSettings: Codable, Equatable, Sendable {
    /// Gesture that stops a recording (starting is always a double-tap of Fn).
    public var stopGesture: StopGesture = .singleTapFn
    /// Return / Enter also stops a recording (the key press is swallowed).
    public var returnStops: Bool = true
    /// ⌃⌥Space toggles recording, for keyboards without a usable Fn key.
    public var fallbackShortcutEnabled: Bool = true
    /// Maximum gap between the two taps of a double-tap, in seconds.
    public var doubleTapWindow: Double = 0.40
    /// WhisperKit model folder name, e.g. "openai_whisper-small.en".
    public var transcriptionModel: String = "openai_whisper-small.en"
    /// Show the in-progress transcript under the indicator (debugging aid).
    public var showLiveText: Bool = false

    public init() {}

    public init(from decoder: any Decoder) throws {
        // Decode leniently so adding fields never wipes existing preferences.
        let defaults = DictationSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stopGesture = try c.decodeIfPresent(StopGesture.self, forKey: .stopGesture) ?? defaults.stopGesture
        returnStops = try c.decodeIfPresent(Bool.self, forKey: .returnStops) ?? defaults.returnStops
        fallbackShortcutEnabled = try c.decodeIfPresent(Bool.self, forKey: .fallbackShortcutEnabled) ?? defaults.fallbackShortcutEnabled
        doubleTapWindow = try c.decodeIfPresent(Double.self, forKey: .doubleTapWindow) ?? defaults.doubleTapWindow
        transcriptionModel = try c.decodeIfPresent(String.self, forKey: .transcriptionModel) ?? defaults.transcriptionModel
        showLiveText = try c.decodeIfPresent(Bool.self, forKey: .showLiveText) ?? defaults.showLiveText
    }
}
