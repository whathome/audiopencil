import Foundation

/// One dictation as an Obsidian note (PRD "Vault layout" and "Frontmatter written on every note").
public struct Note: Codable, Equatable, Sendable, Identifiable {
    public enum Mode: String, Codable, Sendable {
        case quick
        case longForm = "long-form"
        case meeting
    }

    public enum Status: String, Codable, Sendable {
        case needsReview = "needs-review"
        case reviewed
        case actioned
    }

    /// What happens to the note and its audio over time (the Retention board view).
    public enum Retention: String, Codable, Sendable, CaseIterable {
        /// Audio is removed after a year; the note stays.
        case regular
        /// Kept forever.
        case archive
        /// The app deletes the note and its audio (to the trash) next time it checks.
        case delete
    }

    public var id: UUID
    public var title: String
    public var styleID: String
    public var status: Status
    public var recorded: Date
    /// Seconds of audio.
    public var duration: TimeInterval
    public var device: String
    public var mode: Mode
    public var tags: [String]
    public var retention: Retention = .regular
    /// Vault folder the note lands in (the style's landing zone), e.g. "/Dictation".
    public var folder: String
    /// Vault path of the kept audio, e.g. "/Audio Pencil/Recordings/2026-10-19 1430 Title.m4a".
    public var audioPath: String?
    /// The styled text (or the transcript for raw).
    public var body: String
    /// Raw transcript, shown in a collapsed callout under rewritten text.
    public var transcript: String?
    /// Whisper code of the spoken language.
    public var language: String

    public init(
        id: UUID = UUID(), title: String, styleID: String, status: Status, recorded: Date, duration: TimeInterval,
        device: String = "mac", mode: Mode, tags: [String] = [], folder: String, audioPath: String? = nil,
        language: String = "en", body: String, transcript: String? = nil
    ) {
        self.language = language
        self.id = id
        self.title = title
        self.styleID = styleID
        self.status = status
        self.recorded = recorded
        self.duration = duration
        self.device = device
        self.mode = mode
        self.tags = tags
        self.folder = folder
        self.audioPath = audioPath
        self.body = body
        self.transcript = transcript
    }
}

/// How notes are written. Obsidian layout uses Obsidian's embeds and callouts and gets the review board;
/// plain layout is standard Markdown any editor reads (and Obsidian too, so a plain folder can become a
/// vault later without rewriting notes).
public enum NoteLayout: String, Codable, Sendable, CaseIterable {
    case obsidian
    case plain
}

public enum NoteRenderer {
    /// "2026-10-19 1430 Suggested title" (no extension). PRD filename rule; "-2" on collision is
    /// added at upload time.
    public static func baseName(for note: Note, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: note.recorded)
        let stamp = String(format: "%04d-%02d-%02d %02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        let title = safeTitle(note.title)
        return title.isEmpty ? stamp : "\(stamp) \(title)"
    }

    public static func notePath(for note: Note, timeZone: TimeZone = .current) -> String {
        let folder = note.folder.split(separator: "/").joined(separator: "/")
        let name = baseName(for: note, timeZone: timeZone) + ".md"
        return folder.isEmpty ? "/" + name : "/\(folder)/\(name)"
    }

    /// Strips characters that break file names or Obsidian links, and keeps titles short.
    public static func safeTitle(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]\n\r\t")
        var cleaned = title.components(separatedBy: forbidden).joined(separator: " ")
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        if cleaned.count > 60 {
            cleaned = String(cleaned.prefix(60))
            if let space = cleaned.lastIndex(of: " "), cleaned.distance(from: cleaned.startIndex, to: space) > 30 {
                cleaned = String(cleaned[..<space])
            }
        }
        return cleaned
    }

    /// A title when the model can't suggest one: the first few words of what was said.
    public static func fallbackTitle(from text: String) -> String {
        let words = text.split { $0.isWhitespace }.prefix(7).joined(separator: " ")
        return safeTitle(words.trimmingCharacters(in: CharacterSet(charactersIn: ",;:.!?")))
    }

    public static func markdown(for note: Note, timeZone: TimeZone = .current, layout: NoteLayout = .obsidian) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]

        var lines = ["---"]
        lines.append("type: audio-pencil")
        lines.append("style: \(YAMLText.scalar(note.styleID))")
        lines.append("status: \(note.status.rawValue)")
        lines.append("recorded: \(formatter.string(from: note.recorded))")
        lines.append("duration: \(Int(note.duration.rounded()))")
        lines.append("device: \(YAMLText.scalar(note.device))")
        lines.append("mode: \(note.mode.rawValue)")
        lines.append("language: \(YAMLText.scalar(note.language))")
        lines.append("retention: \(note.retention.rawValue)")
        if note.tags.isEmpty {
            lines.append("tags: []")
        } else {
            lines.append("tags:")
            lines += note.tags.map { "  - \(YAMLText.scalar($0))" }
        }
        if let audio = note.audioPath {
            switch layout {
            case .obsidian: lines.append("audio: \(YAMLText.scalar("[[\(linkTarget(audio))]]"))")
            case .plain: lines.append("audio: \(YAMLText.scalar(linkTarget(audio)))")
            }
        }
        lines.append("---")
        lines.append("")
        if let audio = note.audioPath {
            switch layout {
            case .obsidian: lines.append("![[\(linkTarget(audio))]]")
            case .plain: lines.append("[" + String(localized: "Audio", bundle: .module) + "](\(relativeLink(from: note.folder, to: audio)))")
            }
            lines.append("")
        }
        lines.append(note.body.trimmingCharacters(in: .whitespacesAndNewlines))
        if let transcript = note.transcript?.trimmingCharacters(in: .whitespacesAndNewlines), !transcript.isEmpty {
            lines.append("")
            switch layout {
            case .obsidian:
                lines.append("> [!quote]- " + String(localized: "Transcript", bundle: .module))
                lines += transcript.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> \($0)" }
            case .plain:
                lines.append("## " + String(localized: "Transcript", bundle: .module))
                lines.append("")
                lines.append(transcript)
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A standard Markdown link from a note in `folder` to a vault file: relative, spaces encoded.
    /// "/Audio Pencil/Notes" → "/Audio Pencil/Recordings/a b.m4a" gives "../Recordings/a%20b.m4a".
    public static func relativeLink(from folder: String, to path: String) -> String {
        let from = folder.split(separator: "/").map(String.init)
        let to = path.split(separator: "/").map(String.init)
        var common = 0
        while common < min(from.count, to.count - 1), from[common] == to[common] { common += 1 }
        let parts = Array(repeating: "..", count: from.count - common) + to[common...]
        return parts.map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "()"))) ?? $0 }
            .joined(separator: "/")
    }

    /// Obsidian links use vault-relative paths without a leading slash.
    private static func linkTarget(_ path: String) -> String {
        path.hasPrefix("/") ? String(path.dropFirst()) : path
    }
}
