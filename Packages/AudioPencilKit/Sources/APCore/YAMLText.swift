import Foundation

/// Small YAML-writing helpers shared by the settings file and note frontmatter.
public enum YAMLText {
    private static let reserved: Set<String> = ["true", "false", "yes", "no", "on", "off", "null", "~", "y", "n"]

    /// Plain when unambiguous, otherwise double-quoted with escapes.
    public static func scalar(_ value: String) -> String {
        let plain = value.range(of: #"^[A-Za-z][A-Za-z0-9 ._/-]*$"#, options: .regularExpression) != nil
            && !value.hasSuffix(" ")
            && !reserved.contains(value.lowercased())
        if plain { return value }
        var escaped = ""
        for character in value.unicodeScalars {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\t": escaped += "\\t"
            case "\r": escaped += "\\r"
            default: escaped.unicodeScalars.append(character)
            }
        }
        return "\"\(escaped)\""
    }
}
