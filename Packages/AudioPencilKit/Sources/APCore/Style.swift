import Foundation

/// A named way of turning a transcript into text (PRD "Styles").
public struct Style: Codable, Identifiable, Equatable, Hashable, Sendable {
    public enum Intensity: String, Codable, CaseIterable, Sendable {
        /// Remove filler, fix punctuation, add paragraphs; never change wording.
        case light
        /// Smooth sentences and fix grammar; keep the meaning and most phrasing.
        case moderate
        /// Restructure freely into well-written text.
        case heavy
    }

    public enum Tone: String, Codable, CaseIterable, Sendable {
        case asSpoken, casual, professional, business, likeMe
    }

    public enum Length: String, Codable, CaseIterable, Sendable {
        case asSpoken, shorter, brief
    }

    public enum Mode: String, Codable, CaseIterable, Sendable {
        case quick, longForm, both
    }

    public var id: String
    public var name: String
    /// Number key that selects it while recording (1–9). Raw is always 0.
    public var shortcut: Int?
    /// Pass the transcript through untouched; no language model.
    public var isRaw: Bool
    /// What the model is asked to do, in plain words. Editable on the Styles page.
    public var instructions: String
    public var intensity: Intensity
    public var tone: Tone
    public var length: Length
    public var suggestTags: Bool
    /// Only applies to long-form recordings; quick dictation never extracts action items.
    public var extractActionItems: Bool
    public var mode: Mode
    public var keepAudio: Bool
    /// Vault folder for notes (milestone 4/5).
    public var folder: String?
    public var isEnabled: Bool

    public init(
        id: String, name: String, shortcut: Int?, isRaw: Bool = false, instructions: String,
        intensity: Intensity, tone: Tone, length: Length, suggestTags: Bool = false,
        extractActionItems: Bool = false, mode: Mode = .both, keepAudio: Bool = false,
        folder: String? = nil, isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.shortcut = shortcut
        self.isRaw = isRaw
        self.instructions = instructions
        self.intensity = intensity
        self.tone = tone
        self.length = length
        self.suggestTags = suggestTags
        self.extractActionItems = extractActionItems
        self.mode = mode
        self.keepAudio = keepAudio
        self.folder = folder
        self.isEnabled = isEnabled
    }
}

extension Style {
    public static let raw = Style(
        id: "raw", name: "Raw transcript", shortcut: 0, isRaw: true,
        instructions: "Paste exactly what was said.",
        intensity: .light, tone: .asSpoken, length: .asSpoken
    )

    /// The everyday rewrite: what you meant, cleanly written. Not in the PRD's preset list;
    /// added as the double-tap default because Diary is too literal and Professional too structured
    /// for pasting into an email or chat.
    public static let polished = Style(
        id: "polished", name: "Polished", shortcut: 1,
        instructions: """
            Rewrite this as clear, natural written text: remove filler and false starts, fix grammar, smooth \
            awkward phrasing. Keep the meaning, details, voice and length. No headings or bullets.
            """,
        intensity: .moderate, tone: .asSpoken, length: .asSpoken
    )

    public static let diary = Style(
        id: "diary", name: "Diary", shortcut: 2,
        instructions: """
            Tidy this spoken diary entry. Remove filler words (um, uh, like, you know), false starts and \
            accidental repeats. Fix punctuation and capitalisation, and break it into paragraphs where the \
            topic shifts. Keep every other word exactly as spoken, in full sentences: don't shorten, rephrase, \
            summarise, reorder or add anything.
            """,
        intensity: .light, tone: .asSpoken, length: .asSpoken, suggestTags: true, keepAudio: true
    )

    public static let professional = Style(
        id: "professional", name: "Professional", shortcut: 3,
        instructions: """
            Write in the first person, as me ("I'm…", "we decided…"), never "the speaker". A short summary \
            paragraph, then the key points as bullets grouped by theme. Keep facts, names, numbers and \
            decisions; drop rambling.
            """,
        intensity: .heavy, tone: .professional, length: .shorter, suggestTags: true, extractActionItems: true
    )

    /// Uses the user's writing samples as examples; enabled in milestone 6.
    public static let likeMe = Style(
        id: "like-me", name: "Like me", shortcut: 4,
        instructions: "Rewrite this the way I write, matching the tone and habits of my writing samples.",
        intensity: .moderate, tone: .likeMe, length: .asSpoken, isEnabled: false
    )

    public static let presets: [Style] = [.raw, .polished, .diary, .professional, .likeMe]
}
