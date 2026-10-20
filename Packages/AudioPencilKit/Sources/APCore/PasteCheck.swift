import Foundation

/// What Accessibility shows of the focused field: its text, when the app exposes it, or at least its length.
public struct FieldState: Equatable, Sendable {
    public var value: String?
    public var length: Int?

    public init(value: String?, length: Int?) {
        self.value = value
        self.length = length ?? value.map { ($0 as NSString).length }
    }
}

/// Did a pasted dictation reach the field? Two signals: the field's text before and after the paste, and
/// whether an app asked for the clipboard's text (it's offered on request, so a paste has to ask).
public enum PasteCheck {
    public enum Evidence: Equatable, Sendable {
        /// The text, or something its size, appeared in the field.
        case arrived
        /// The field is readable and didn't change.
        case unchanged
        /// No readable field (many Electron apps and web editors), or a change too small to judge.
        case unknown
    }

    public enum Verdict: Equatable, Sendable {
        case confirmed
        case unconfirmed
    }

    public static func evidence(before: FieldState?, after: FieldState?, pasted: String) -> Evidence {
        guard let before, let after else { return .unknown }
        if let old = before.value, let new = after.value {
            if old == new { return .unchanged }
            // Apps tidy pasted text (line endings, smart quotes, trailing spaces), so look for a stretch of it.
            let probes = probes(of: pasted)
            let oldText = normalized(old), newText = normalized(new)
            if !probes.isEmpty, probes.allSatisfy({ occurrences(of: $0, in: newText) > occurrences(of: $0, in: oldText) }) {
                return .arrived
            }
        }
        if let old = before.length, let new = after.length {
            let pastedLength = (pasted as NSString).length
            if new - old >= max(1, pastedLength / 2) { return .arrived }
            if new == old, before.value == nil || after.value == nil { return .unchanged }
        }
        return .unknown
    }

    /// The clipboard read is the main signal: an app can't paste without it. A readable field that didn't
    /// change overrules it, since something else may have asked.
    public static func verdict(clipboardRead: Bool, evidence: Evidence) -> Verdict {
        switch evidence {
        case .arrived: .confirmed
        case .unchanged: .unconfirmed
        case .unknown: clipboardRead ? .confirmed : .unconfirmed
        }
    }

    /// The start and end of the pasted text, up to 40 characters each.
    static func probes(of text: String) -> [String] {
        let clean = normalized(text)
        guard !clean.isEmpty else { return [] }
        let head = String(clean.prefix(40))
        let tail = String(clean.suffix(40))
        return head == tail ? [head] : [head, tail]
    }

    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "[“”]", with: "\"", options: .regularExpression)
            .replacingOccurrences(of: "[‘’]", with: "'", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}
