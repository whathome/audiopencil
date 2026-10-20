import Foundation
import Yams

/// Pieces of a YAML document that can be parsed on their own, so a mistake in one part doesn't
/// cost the rest. Used to repair the settings file and the board without losing valid edits.
enum YAMLSalvage {
    /// Splits at top-level keys ("key:" at column 0). Returns (key, chunk text) in order.
    static func topLevelChunks(_ yaml: String) -> [(key: String, text: String)] {
        var chunks: [(String, [String])] = []
        for line in yaml.components(separatedBy: "\n") {
            if let first = line.first, !first.isWhitespace, first != "#", first != "-",
               let colon = line.firstIndex(of: ":") {
                chunks.append((String(line[..<colon]).trimmingCharacters(in: .whitespaces), [line]))
            } else if !chunks.isEmpty {
                chunks[chunks.count - 1].1.append(line)
            }
        }
        return chunks.map { ($0.0, $0.1.joined(separator: "\n")) }
    }

    /// Splits the items of a block sequence ("  - …") under a key chunk. Each item's text is
    /// re-indented to parse on its own as a one-element sequence.
    static func sequenceItems(_ chunk: String) -> [String] {
        var items: [[String]] = []
        var itemIndent: Int?
        for line in chunk.components(separatedBy: "\n").dropFirst() {
            let indent = line.prefix { $0 == " " }.count
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("- "), itemIndent == nil || indent == itemIndent {
                itemIndent = indent
                items.append([line])
            } else if !items.isEmpty {
                items[items.count - 1].append(line)
            }
        }
        guard let itemIndent else { return [] }
        return items.map { lines in
            lines.map { $0.count >= itemIndent ? String($0.dropFirst(itemIndent)) : $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
        }
    }

    static func parses(_ yaml: String) -> Bool {
        (try? Yams.load(yaml: yaml)) != nil
    }
}
