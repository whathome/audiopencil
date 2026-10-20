import APCore
import Foundation

/// What the interface shows for a style. Styles are data shared through the vault (and their instructions
/// are the English prompt the model reads), so presets that still have their default name get a translated
/// name and a translated summary; anything the user renamed or wrote is shown as written.
extension Style {
    private var preset: Style? { Style.presets.first { $0.id == id } }

    var displayName: String {
        guard let preset, name == preset.name else { return name }
        return switch id {
        case Style.raw.id: String(localized: "Raw transcript")
        case Style.polished.id: String(localized: "Polished")
        case Style.diary.id: String(localized: "Diary")
        case Style.professional.id: String(localized: "Professional")
        case Style.likeMe.id: String(localized: "Like me")
        default: name
        }
    }

    /// Short name for the recording indicator.
    var shortDisplayName: String { isRaw ? String(localized: "Raw") : displayName }

    var displayDescription: String {
        #if os(macOS)
        if isRaw { return String(localized: "Pastes exactly what you said. Holding Fn always gives you this.") }
        #else
        if isRaw { return String(localized: "Exactly what you said, as transcribed.") }
        #endif
        // A preset still under its default name gets the translated summary; the editor shows the real prompt.
        guard let preset, name == preset.name else { return instructions }
        return switch id {
        case Style.polished.id: String(localized: "Rewrites it as clear, natural written text: no filler or false starts, grammar fixed, meaning, details, voice and length kept. No headings or bullets.")
        case Style.diary.id: String(localized: "Tidies a spoken diary entry: removes filler and repeats, fixes punctuation, adds paragraphs. Never changes your wording.")
        case Style.professional.id: String(localized: "A short summary paragraph, then the key points as bullets grouped by theme. Keeps facts, names, numbers and decisions; drops rambling.")
        case Style.likeMe.id: String(localized: "Rewrites it the way you write, matching the tone and habits of your writing samples.")
        default: instructions
        }
    }
}
