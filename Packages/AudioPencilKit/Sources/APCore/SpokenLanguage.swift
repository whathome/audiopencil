import Foundation

/// A language Whisper can transcribe, identified by Whisper's code ("en", "fr", "yue").
/// One language per recording; the app starts in the last one used.
public struct SpokenLanguage: Hashable, Sendable, Identifiable, Codable {
    public let code: String
    public var id: String { code }

    public init(code: String) {
        self.code = code.lowercased()
    }

    public static let english = SpokenLanguage(code: "en")

    public var isEnglish: Bool { code == "en" }

    /// Short badge for the recording pill, e.g. "FR".
    public var badge: String { code.uppercased() }

    /// Name in the user's interface language, e.g. "French" or "français".
    public func name(in locale: Locale = .current) -> String {
        if let name = locale.localizedString(forLanguageCode: Self.localeCode(code)) {
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        return code
    }

    /// English name, for prompts: small models follow "Write in French" better than a code.
    public var englishName: String { name(in: Locale(identifier: "en")) }

    /// Whisper's codes that Foundation knows under another code.
    private static func localeCode(_ code: String) -> String {
        switch code {
        case "jw": "jv" // Javanese
        default: code
        }
    }

    /// Every language Whisper transcribes (large-v3 set, 100 languages).
    public static let whisperCodes: [String] = [
        "en", "zh", "de", "es", "ru", "ko", "fr", "ja", "pt", "tr", "pl", "ca", "nl", "ar", "sv", "it",
        "id", "hi", "fi", "vi", "he", "uk", "el", "ms", "cs", "ro", "da", "hu", "ta", "no", "th", "ur",
        "hr", "bg", "lt", "la", "mi", "ml", "cy", "sk", "te", "fa", "lv", "bn", "sr", "az", "sl", "kn",
        "et", "mk", "br", "eu", "is", "hy", "ne", "mn", "bs", "kk", "sq", "sw", "gl", "mr", "pa", "si",
        "km", "sn", "yo", "so", "af", "oc", "ka", "be", "tg", "sd", "gu", "am", "yi", "lo", "uz", "fo",
        "ht", "ps", "tk", "nn", "mt", "sa", "lb", "my", "bo", "tl", "mg", "as", "tt", "haw", "ln", "ha",
        "ba", "jw", "su", "yue",
    ]

    /// All of them, sorted by name in the interface language.
    public static func all(in locale: Locale = .current) -> [SpokenLanguage] {
        whisperCodes.map(SpokenLanguage.init).sorted { $0.name(in: locale).localizedCompare($1.name(in: locale)) == .orderedAscending }
    }

    /// Starting list for a new install: English, then the Mac's preferred languages Whisper knows.
    public static func defaultCodes(preferred: [String] = Locale.preferredLanguages) -> [String] {
        var codes = ["en"]
        for identifier in preferred {
            let code = Locale(identifier: identifier).language.languageCode?.identifier ?? identifier
            let whisper = code == "nb" ? "no" : code // Norwegian Bokmål is "no" to Whisper
            if whisperCodes.contains(whisper), !codes.contains(whisper) { codes.append(whisper) }
        }
        return codes
    }
}

/// Remembers which language was spoken in which app, on this Mac only (never synced): dictating in
/// Mail in French and in Xcode in English each start in the right language.
public struct LanguageMemory: Codable, Equatable, Sendable {
    /// App bundle identifier → Whisper language code.
    public private(set) var perApp: [String: String] = [:]
    public private(set) var lastUsed: String?

    public init() {}

    /// The language for `app`: what was last spoken there, else the last language used anywhere,
    /// else English.
    public func language(forApp app: String?) -> SpokenLanguage {
        SpokenLanguage(code: app.flatMap { perApp[$0] } ?? lastUsed ?? "en")
    }

    public mutating func remember(_ language: SpokenLanguage, forApp app: String?) {
        lastUsed = language.code
        if let app { perApp[app] = language.code }
    }

    public mutating func forget(app: String) {
        perApp[app] = nil
    }
}
