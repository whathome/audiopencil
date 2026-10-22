import APCore
import APStorage
import Foundation

/// Obsidian's Daily notes core plugin, as this vault has it set up: whether it's on, and where and how it
/// makes each day's note (`.obsidian/core-plugins.json` and `.obsidian/daily-notes.json`).
public struct DailyNotesSetup: Equatable, Sendable {
    /// Folder for daily notes, vault-relative ("" for the top).
    public var folder: String
    /// Obsidian (moment.js) date format, which may contain folders: "YYYY/MM/YYYY-MM-DD".
    public var format: String
    /// Vault-relative template path, if any (".md" optional, as Obsidian stores it).
    public var template: String?

    public init(folder: String = "", format: String = "YYYY-MM-DD", template: String? = nil) {
        self.folder = folder
        self.format = format.isEmpty ? "YYYY-MM-DD" : format
        self.template = template?.isEmpty == true ? nil : template
    }

    /// Whether the plugin is on in `core-plugins.json`: an object of switches (current Obsidian) or a
    /// list of enabled ids (older versions).
    public static func isEnabled(corePlugins data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return false }
        if let switches = json as? [String: Any] { return switches["daily-notes"] as? Bool == true }
        if let enabled = json as? [String] { return enabled.contains("daily-notes") }
        return false
    }

    /// The plugin's settings; missing keys take Obsidian's defaults.
    public static func settings(_ data: Data?) -> DailyNotesSetup {
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return DailyNotesSetup() }
        return DailyNotesSetup(folder: json["folder"] as? String ?? "", format: json["format"] as? String ?? "", template: json["template"] as? String)
    }

    /// Reads the vault's setup; nil when Daily notes is off (or the folder isn't an Obsidian vault).
    public static func load(from provider: any StorageProvider, vaultPath: String) async -> DailyNotesSetup? {
        let config = StoragePath.join(vaultPath, ".obsidian")
        guard let plugins = try? await provider.read(StoragePath.join(config, "core-plugins.json")).data,
              isEnabled(corePlugins: plugins)
        else { return nil }
        let settings = try? await provider.read(StoragePath.join(config, "daily-notes.json")).data
        return Self.settings(settings)
    }

    /// Vault path of the daily note for `date`: "/Daily/2026-10-21.md".
    public func path(for date: Date, calendar: Calendar = .current) -> String {
        let name = MomentFormat.format(date, format, calendar: calendar)
        return StoragePath.join("/", folder, name + ".md")
    }

    /// The template's vault path with ".md", if a template is set.
    public var templatePath: String? {
        guard let template else { return nil }
        let path = StoragePath.join("/", template)
        return path.hasSuffix(".md") ? path : path + ".md"
    }
}

/// Obsidian's template variables: {{title}}, {{date}}, {{time}}, {{date:FORMAT}}, {{time:FORMAT}}.
public enum DailyTemplate {
    public static func fill(_ template: String, title: String, date: Date, dateFormat: String = "YYYY-MM-DD", timeFormat: String = "HH:mm", calendar: Calendar = .current) -> String {
        var text = template.replacingOccurrences(of: "{{title}}", with: title)
        let pattern = #"\{\{\s*(date|time)\s*(?::([^}]*))?\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed()
        for match in matches {
            guard let range = Range(match.range, in: text), let kind = Range(match.range(at: 1), in: text).map({ String(text[$0]) }) else { continue }
            let custom = Range(match.range(at: 2), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespaces) }
            let format = (custom?.isEmpty == false ? custom : nil) ?? (kind == "date" ? dateFormat : timeFormat)
            text.replaceSubrange(range, with: MomentFormat.format(date, format, calendar: calendar))
        }
        return text
    }
}

/// Adding a line to a note: at the end, or at the end of a section under a heading (added if missing).
public enum NoteAppend {
    /// `heading`: e.g. "## Audio Pencil"; nil or blank appends at the end of the note.
    public static func apply(_ entry: String, to existing: String, heading: String?) -> String {
        var text = existing
        let heading = heading?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !heading.isEmpty else {
            if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
            return text + entry + "\n"
        }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == heading }) else {
            // No section yet: add it at the end, a blank line apart.
            var result = lines.joined(separator: "\n")
            if !result.isEmpty { result += result.hasSuffix("\n") ? "\n" : "\n\n" }
            return result + heading + "\n" + entry + "\n"
        }
        // The section runs to the next heading of the same or a higher level.
        let level = heading.prefix { $0 == "#" }.count
        var end = lines.count
        for index in lines.indices where index > start {
            let line = lines[index]
            let hashes = line.prefix { $0 == "#" }.count
            if hashes > 0, hashes <= max(level, 1), line.dropFirst(hashes).first == " " {
                end = index
                break
            }
        }
        // After the section's last non-blank line.
        var insert = end
        while insert > start + 1, lines[insert - 1].trimmingCharacters(in: .whitespaces).isEmpty { insert -= 1 }
        lines.insert(entry, at: insert)
        return lines.joined(separator: "\n") + "\n"
    }
}

/// The moment.js tokens Obsidian date formats use. Text in [brackets] is literal. Names are English
/// (moment's default locale).
public enum MomentFormat {
    static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let tokens = ["YYYY", "YY", "MMMM", "MMM", "MM", "M", "DDDD", "DDD", "Do", "DD", "D", "dddd", "ddd", "dd", "d", "HH", "H", "hh", "h", "mm", "m", "ss", "s", "A", "a", "ww", "w", "WW", "W", "gggg", "GGGG", "Q"]

    public static func format(_ date: Date, _ format: String, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute, .second, .weekOfYear, .yearForWeekOfYear, .quarter], from: date)
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let isoWeek = iso.component(.weekOfYear, from: date)
        let isoYear = iso.component(.yearForWeekOfYear, from: date)
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        func pad(_ value: Int, _ width: Int) -> String { String(format: "%0\(width)d", value) }
        var result = ""
        var index = format.startIndex
        while index < format.endIndex {
            if format[index] == "[", let close = format[index...].firstIndex(of: "]") {
                result += format[format.index(after: index)..<close]
                index = format.index(after: close)
                continue
            }
            let rest = format[index...]
            guard let token = tokens.first(where: { rest.hasPrefix($0) }) else {
                result.append(format[index])
                index = format.index(after: index)
                continue
            }
            let hour = c.hour ?? 0
            switch token {
            case "YYYY": result += pad(c.year ?? 0, 4)
            case "YY": result += pad((c.year ?? 0) % 100, 2)
            case "MMMM": result += months[(c.month ?? 1) - 1]
            case "MMM": result += String(months[(c.month ?? 1) - 1].prefix(3))
            case "MM": result += pad(c.month ?? 0, 2)
            case "M": result += "\(c.month ?? 0)"
            case "DDDD": result += pad(dayOfYear, 3)
            case "DDD": result += "\(dayOfYear)"
            case "Do": result += ordinal(c.day ?? 0)
            case "DD": result += pad(c.day ?? 0, 2)
            case "D": result += "\(c.day ?? 0)"
            case "dddd": result += weekdays[(c.weekday ?? 1) - 1]
            case "ddd": result += String(weekdays[(c.weekday ?? 1) - 1].prefix(3))
            case "dd": result += String(weekdays[(c.weekday ?? 1) - 1].prefix(2))
            case "d": result += "\((c.weekday ?? 1) - 1)"
            case "HH": result += pad(hour, 2)
            case "H": result += "\(hour)"
            case "hh": result += pad(hour % 12 == 0 ? 12 : hour % 12, 2)
            case "h": result += "\(hour % 12 == 0 ? 12 : hour % 12)"
            case "mm": result += pad(c.minute ?? 0, 2)
            case "m": result += "\(c.minute ?? 0)"
            case "ss": result += pad(c.second ?? 0, 2)
            case "s": result += "\(c.second ?? 0)"
            case "A": result += hour < 12 ? "AM" : "PM"
            case "a": result += hour < 12 ? "am" : "pm"
            case "ww": result += pad(c.weekOfYear ?? 0, 2)
            case "w": result += "\(c.weekOfYear ?? 0)"
            case "WW": result += pad(isoWeek, 2)
            case "W": result += "\(isoWeek)"
            case "gggg": result += pad(c.yearForWeekOfYear ?? 0, 4)
            case "GGGG": result += pad(isoYear, 4)
            case "Q": result += "\(c.quarter ?? ((c.month ?? 1) - 1) / 3 + 1)"
            default: result += token
            }
            index = format.index(index, offsetBy: token.count)
        }
        return result
    }

    static func ordinal(_ day: Int) -> String {
        let suffix = switch (day % 10, day % 100) {
        case (_, 11...13): "th"
        case (1, _): "st"
        case (2, _): "nd"
        case (3, _): "rd"
        default: "th"
        }
        return "\(day)\(suffix)"
    }
}
