import APCore
import Foundation
import Yams

/// Reads and edits a note's YAML frontmatter without disturbing anything else in the file:
/// edits are line-based, so formatting, comments and the body stay exactly as the user left them.
public enum NoteFrontmatter {
    /// Frontmatter lines (between the opening and closing ---) and the range they occupy.
    private static func bounds(_ text: String) -> (lines: [String], end: Int)? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return nil }
        return (lines, end)
    }

    /// All frontmatter properties, parsed as YAML. Empty if there's none or it doesn't parse.
    public static func properties(_ text: String) -> [String: Any] {
        guard let (lines, end) = bounds(text) else { return [:] }
        let yaml = lines[1..<end].joined(separator: "\n")
        return ((try? Yams.load(yaml: yaml)) as? [String: Any]) ?? [:]
    }

    public static func string(_ key: String, in text: String) -> String? {
        switch properties(text)[key] {
        case let value as String: value
        case let value as Date: ISO8601DateFormatter().string(from: value)
        case let value?: "\(value)"
        case nil: nil
        }
    }

    public static func date(_ key: String, in text: String) -> Date? {
        switch properties(text)[key] {
        case let value as Date: return value
        case let value as String:
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: value)
        default: return nil
        }
    }

    /// Sets a top-level scalar (replacing its line, and any indented lines under it) or appends it.
    /// `nil` removes the key.
    public static func setting(_ key: String, to value: String?, in text: String) -> String {
        guard var (lines, end) = bounds(text) else { return text }
        var index = 1
        var found: Int?
        while index < end {
            if lines[index].hasPrefix(key + ":") { found = index; break }
            index += 1
        }
        if let found {
            var stop = found + 1
            while stop < end, lines[stop].hasPrefix(" ") || lines[stop].hasPrefix("\t") || lines[stop].hasPrefix("-") { stop += 1 }
            lines.removeSubrange(found..<stop)
            end -= stop - found
            if let value { lines.insert("\(key): \(value)", at: found) }
        } else if let value {
            lines.insert("\(key): \(value)", at: end)
        }
        return lines.joined(separator: "\n")
    }

    /// Removes body lines that embed the given file (e.g. "![[Audio Pencil/Recordings/x.m4a]]").
    public static func removingEmbeds(of target: String, in text: String) -> String {
        guard let (lines, end) = bounds(text) else { return text }
        let name = target.hasPrefix("/") ? String(target.dropFirst()) : target
        // Same encoding as NoteRenderer.relativeLink, so the file name matches the link's last part.
        let encoded = NoteRenderer.relativeLink(from: "/", to: name).split(separator: "/").last.map(String.init)
        let body = lines[(end + 1)...].filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let obsidianEmbed = trimmed.hasPrefix("![[") && trimmed.contains(name)
            // Plain layout: "[Audio](../Recordings/2026-10-19%201430%20x.m4a)"
            let markdownLink = trimmed.hasPrefix("[") && trimmed.contains("](") && encoded.map { trimmed.contains($0) } == true
            return !(obsidianEmbed || markdownLink)
        }
        return (lines[...end] + body).joined(separator: "\n")
    }

    /// "[[Audio Pencil/Recordings/x.m4a]]" (Obsidian layout) or "Audio Pencil/Recordings/x.m4a" (plain)
    /// → "/Audio Pencil/Recordings/x.m4a"
    public static func linkTarget(_ link: String) -> String? {
        var value = link.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("[["), value.hasSuffix("]]") {
            value = String(value.dropFirst(2).dropLast(2))
        } else if value.hasPrefix("[") || value.contains("://") {
            return nil
        }
        if let bar = value.firstIndex(of: "|") { value = String(value[..<bar]) }
        return value.isEmpty ? nil : "/" + value
    }
}
