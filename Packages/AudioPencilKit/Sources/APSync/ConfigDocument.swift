import APCore
import Foundation
import Yams

public enum ConfigError: LocalizedError, Equatable {
    case missingYAMLBlock
    case invalidYAML(String)

    public var errorDescription: String? {
        switch self {
        case .missingYAMLBlock: String(localized: "The settings file has no ```yaml block.", bundle: .module)
        case .invalidYAML(let detail): String(localized: "The settings file has a YAML error: \(detail)", bundle: .module)
        }
    }
}

/// The settings file: a short note explaining itself, then one fenced YAML block.
/// Rendered by hand so instructions come out as readable multi-line blocks; parsed with Yams,
/// so whatever valid YAML someone types in Obsidian is accepted.
public enum ConfigDocument {
    public static let folderName = "Audio Pencil"
    public static let fileName = "Settings.md"

    public static func render(_ config: SharedConfig) -> String {
        """
        # Audio Pencil settings

        Shared by Audio Pencil on all your devices and kept in sync through this vault. Edit the YAML \
        below; the app picks up changes within a minute. Styles, vocabulary and tags are shared; each \
        device has its own section under `devices`. If the YAML has a mistake, the app stops syncing \
        until it's fixed (nothing gets overwritten).

        ```yaml
        \(renderYAML(config))```

        """
    }

    public static func parse(_ markdown: String) throws -> SharedConfig {
        let lines = markdown.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("```yaml") }) else {
            throw ConfigError.missingYAMLBlock
        }
        let afterStart = lines[(start + 1)...]
        guard let end = afterStart.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "```" }) else {
            throw ConfigError.missingYAMLBlock
        }
        let yaml = afterStart[..<end].joined(separator: "\n")
        do {
            if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return SharedConfig() }
            return try YAMLDecoder().decode(SharedConfig.self, from: yaml)
        } catch let error as YamlError {
            throw ConfigError.invalidYAML(describe(error, lineOffset: start + 1))
        } catch let error as DecodingError {
            throw ConfigError.invalidYAML(describe(error, lineOffset: start + 1))
        } catch {
            throw ConfigError.invalidYAML(error.localizedDescription)
        }
    }

    /// Syntax errors arrive wrapped in a DecodingError; type mistakes name the key path.
    private static func describe(_ error: DecodingError, lineOffset: Int) -> String {
        switch error {
        case .dataCorrupted(let context):
            if let yaml = context.underlyingError as? YamlError { return describe(yaml, lineOffset: lineOffset) }
            return context.debugDescription
        case .typeMismatch(let type, let context):
            return "\(keyPath(context.codingPath)): expected \(type == Int.self || type == Double.self ? "a number" : type == Bool.self ? "true or false" : "\(type)")"
        case .valueNotFound(_, let context):
            return "\(keyPath(context.codingPath)) is missing a value"
        case .keyNotFound(let key, let context):
            return "\(keyPath(context.codingPath + [key])) is required"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func keyPath(_ path: [any CodingKey]) -> String {
        path.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }

    /// Yams reports lines within the YAML block; shift them to lines of the note.
    private static func describe(_ error: YamlError, lineOffset: Int) -> String {
        switch error {
        case .parser(_, let problem, let mark, _), .scanner(_, let problem, let mark, _):
            return "\(problem) (line \(mark.line + lineOffset))"
        default:
            return String(describing: error)
        }
    }

    // MARK: Rendering

    static func renderYAML(_ config: SharedConfig) -> String {
        var out = "version: \(config.version)\n"
        out += list("vocabulary", config.vocabulary)
        let languages = config.languageVocabulary.filter { !$0.value.isEmpty }
        if languages.isEmpty {
            out += "vocabulary_by_language: {}  # e.g. fr: [Loïc-William]\n"
        } else {
            out += "vocabulary_by_language:\n"
            for code in languages.keys.sorted() {
                out += "  " + list("\"\(code)\"", languages[code] ?? []) // quoted: "no" (Norwegian) is a YAML boolean.replacingOccurrences(of: "\n  - ", with: "\n    - ")
            }
        }
        out += list("tags", config.tags)
        out += "expire_regular_audio_after_a_year: \(config.expireRegularAudio)\n"
        if config.styles.isEmpty {
            out += "styles: []\n"
        } else {
            out += "styles:\n"
            for style in config.styles {
                out += "  - id: \(scalar(style.id))\n"
                out += "    name: \(scalar(style.name))\n"
                out += "    shortcut: \(style.shortcut.map(String.init) ?? "null")\n"
                out += "    enabled: \(style.enabled)\n"
                if style.raw { out += "    raw: true\n" }
                out += "    instructions: " + block(style.instructions, indent: 6)
                out += "    intensity: \(scalar(style.intensity))\n"
                out += "    tone: \(scalar(style.tone))\n"
                out += "    length: \(scalar(style.length))\n"
                out += "    mode: \(scalar(style.mode))\n"
                out += "    suggest_tags: \(style.suggestTags)\n"
                out += "    action_items: \(style.actionItems)\n"
                out += "    keep_audio: \(style.keepAudio)\n"
                out += "    folder: \(style.folder.map(scalar) ?? "null")\n"
            }
        }
        if config.writingSamples.isEmpty {
            out += "writing_samples: []\n"
        } else {
            out += "writing_samples:\n"
            for sample in config.writingSamples {
                out += "  - id: \(scalar(sample.id))\n"
                out += "    kind: \(scalar(sample.kind))\n"
                if let prompt = sample.promptID { out += "    prompt: \(scalar(prompt))\n" }
                if let language = sample.language { out += "    language: \(scalar(language))\n" }
                out += "    text: " + block(sample.text, indent: 6)
            }
        }
        if config.devices.isEmpty {
            out += "devices: {}\n"
        } else {
            out += "devices:\n"
            for (name, device) in config.devices.sorted(by: { $0.key < $1.key }) {
                out += "  \(scalar(name)):\n"
                if device.microphones.isEmpty {
                    out += "    microphones: []\n"
                } else {
                    out += "    microphones:\n"
                    for mic in device.microphones {
                        out += "      - name: \(scalar(mic.name))\n        uid: \(scalar(mic.uid))\n"
                    }
                }
                out += "    key: \(scalar(device.key))  # fn, right-option or right-command\n"
                out += "    start: \(scalar(device.start))  # double-tap or single-tap\n"
                out += "    stop: \(scalar(device.stop))\n"
                out += "    shortcut: \(scalar(device.shortcut))  # modifiers + virtual key code; 49 is Space\n"
                out += "    return_stops: \(device.returnStops)\n"
                out += "    hold_for_raw: \(device.holdForRaw)\n"
                out += "    fallback_shortcut: \(device.fallbackShortcut)\n"
                out += "    double_tap_window: \(number(device.doubleTapWindow))\n"
                out += "    warm_mic_on_first_tap: \(device.warmMicOnFirstTap)\n"
                out += "    transcription_model: \(scalar(device.transcriptionModel))  # used for English\n"
                out += "    multilingual_transcription_model: \(scalar(device.multilingualModel))  # every other language\n"
                out += "    " + list("languages", device.languages).replacingOccurrences(of: "\n  - ", with: "\n      - ")
                out += "    writing_model: \(scalar(device.writingModel))\n"
                out += "    pick_style_after_stop: \(device.pickStyleAfterStop)\n"
                out += "    picker_auto_confirm: \(number(device.pickerAutoConfirm))\n"
                out += "    long_form_threshold_seconds: \(number(device.longFormThreshold))\n"
                out += "    save_quick_dictations: \(device.saveQuickDictations)\n"
                out += "    keep_clipboard: \(device.keepClipboard)  # put the clipboard back after a confirmed paste\n"
                out += "    sounds: \(scalar(device.sounds))  # tricorder, soft, chime, click, system or none\n"
                out += "    sound_volume: \(number(device.soundVolume))\n"
            }
        }
        return out
    }

    private static func list(_ key: String, _ values: [String]) -> String {
        guard !values.isEmpty else { return "\(key): []\n" }
        return "\(key):\n" + values.map { "  - \(scalar($0))\n" }.joined()
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.1f", value) : String(value)
    }

    /// Literal block scalar (`|-`): any text, newlines kept, no escaping needed.
    private static func block(_ text: String, indent: Int) -> String {
        guard !text.isEmpty else { return "\"\"\n" }
        let pad = String(repeating: " ", count: indent)
        let body = text.components(separatedBy: "\n").map { $0.isEmpty ? "" : pad + $0 }.joined(separator: "\n")
        return "|-\n" + body + "\n"
    }

    /// Plain when unambiguous, otherwise double-quoted with escapes.
    static func scalar(_ value: String) -> String { YAMLText.scalar(value) }
}
