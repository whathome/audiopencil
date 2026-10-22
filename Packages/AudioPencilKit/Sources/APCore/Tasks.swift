import Foundation

/// Obsidian tasks in the Tasks plugin's format: `- [ ] Send the lease by Friday 📅 2026-10-23`.
/// Dates come from what was said ("by Friday", "starting next Monday"), worked out from when it was said.
public enum TaskLine {
    public static let checkbox = "- [ ] "
    /// Tasks plugin markers.
    public static let dueMarker = "📅"
    public static let startMarker = "🛫"

    /// One task line. Newlines become spaces; dates heard in the text are added as due and start dates.
    public static func make(_ text: String, said: Date, language: String = "en", calendar: Calendar = .current) -> String {
        var description = text.replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // A list marker the model or the speaker left in front.
        if let range = description.range(of: #"^(?:[-*•]\s+|\d+[.)]\s+)"#, options: .regularExpression) {
            description.removeSubrange(range)
        }
        let dates = TaskDates.find(in: description, said: said, language: language, calendar: calendar)
        var line = checkbox + description
        if let start = dates.start { line += " \(startMarker) \(format(start, calendar))" }
        if let due = dates.due { line += " \(dueMarker) \(format(due, calendar))" }
        return line
    }

    static func format(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// A note's "Action items" section, rewritten as Obsidian tasks.
public enum ActionItems {
    /// The section's heading in the languages notes are written in (the model writes it in the spoken one).
    static let headings = [
        "action items", "action item", "action points", "next steps", "to-do", "to do", "todo", "tasks",
        "actions à mener", "actions", "à faire", "tâches", "prochaines étapes",
        "acciones", "tareas", "pendientes", "próximos pasos",
        "aufgaben", "nächste schritte", "azioni", "ações", "tarefas",
    ]
    /// "Nothing to do" answers, which stay as plain text rather than empty tasks.
    static let nothing: Set<String> = ["none", "nothing", "n/a", "aucune", "aucun", "rien", "ninguna", "ninguno", "nada", "keine", "nessuna", "nenhuma"]

    /// Turns the bullets under an action-items heading into `- [ ] …` task lines with dates. Everything else
    /// is left as written.
    public static func asTasks(_ markdown: String, said: Date, language: String = "en", calendar: Calendar = .current) -> String {
        var lines = markdown.components(separatedBy: "\n")
        var inSection = false
        for index in lines.indices {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isHeading(trimmed) {
                inSection = isActionHeading(trimmed)
                continue
            }
            guard inSection else { continue }
            if trimmed.isEmpty { continue }
            guard let item = listItem(trimmed) else {
                inSection = false // a paragraph ends the section
                continue
            }
            if item.hasPrefix("[ ]") || item.hasPrefix("[x]") { continue } // already a task
            let words = item.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".!").union(.whitespaces))
            if nothing.contains(words) {
                lines[index] = item
                continue
            }
            let indent = String(line.prefix { $0 == " " })
            lines[index] = indent + TaskLine.make(item, said: said, language: language, calendar: calendar)
        }
        return lines.joined(separator: "\n")
    }

    /// "**Action items**", "## Action items", "Action items:".
    static func isHeading(_ line: String) -> Bool {
        line.hasPrefix("#") || (line.hasPrefix("**") && line.hasSuffix("**") || line.hasPrefix("**") && line.hasSuffix(":**") || line.hasPrefix("**") && line.hasSuffix("**:"))
            || (line.hasSuffix(":") && !line.hasPrefix("-") && !line.hasPrefix("*") && line.count < 40)
    }

    static func isActionHeading(_ line: String) -> Bool {
        let text = line.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*: ").union(.whitespaces))
        return headings.contains(text)
    }

    /// The text of a bullet or numbered item, or nil for anything else.
    static func listItem(_ line: String) -> String? {
        guard let range = line.range(of: #"^(?:[-*•]|\d+[.)])\s+"#, options: .regularExpression) else { return nil }
        return String(line[range.upperBound...])
    }
}

/// Dictations that start with a trigger phrase ("New task: call the landlord") become a single task.
public enum TaskKeywords {
    public static let defaults = ["new task", "action item", "to do"]

    /// What follows the first matching phrase, cleaned up and capitalised; nil when none matches or nothing
    /// follows. Case, accents, punctuation and "to-do"/"todo"/"to do" spellings don't matter.
    public static func remainder(of text: String, keywords: [String]) -> String? {
        let ordered = keywords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        for keyword in ordered {
            let words = fold(keyword).split(whereSeparator: { $0.isWhitespace || $0 == "-" }).map { NSRegularExpression.escapedPattern(for: String($0)) }
            guard !words.isEmpty else { continue }
            let pattern = #"^[\s\p{P}]*"# + words.joined(separator: #"[\s\-]*"#) + #"(?![\p{L}\p{N}])[\s\p{P}]*"#
            // Regex matching ignores accents only on folded text; folding keeps one character per character.
            let folded = fold(text)
            guard folded.count == text.count,
                  let range = folded.range(of: pattern, options: [.regularExpression, .caseInsensitive])
            else { continue }
            let rest = text.dropFirst(folded.distance(from: folded.startIndex, to: range.upperBound))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard rest.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
            return rest.prefix(1).uppercased() + rest.dropFirst()
        }
        return nil
    }
}

extension TaskKeywords {
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}

/// Due and start dates heard in a task ("by Friday", "starting Monday", "le 23 octobre", "antes del viernes").
/// Relative words count from when they were said. A date is a start date when introduced as one
/// ("starting", "from", "à partir de", "desde"…), otherwise a due date.
public enum TaskDates {
    public struct Found: Equatable {
        public var due: Date?
        public var start: Date?
    }

    public static func find(in text: String, said: Date, language: String = "en", calendar: Calendar = .current) -> Found {
        let words = Words.forLanguage(language)
        let lower = text.lowercased()
        var hits: [(range: Range<String.Index>, date: Date)] = []
        for rule in rules(words) {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
                guard let range = Range(match.range, in: lower),
                      !hits.contains(where: { $0.range.overlaps(range) }),
                      let date = rule.resolve(match, lower, said, calendar)
                else { continue }
                hits.append((range, calendar.startOfDay(for: date)))
            }
        }
        var found = Found()
        for hit in hits.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            let before = lower[lower.index(hit.range.lowerBound, offsetBy: -min(28, lower.distance(from: lower.startIndex, to: hit.range.lowerBound)))..<hit.range.lowerBound]
            let isStart = words.startCues.contains { cueIsClose($0, in: before) }
            if isStart {
                if found.start == nil { found.start = hit.date }
            } else if found.due == nil {
                found.due = hit.date
            }
        }
        return found
    }

    /// The start cue is the last thing before the date ("starting next Monday", "from the 3rd").
    private static func cueIsClose(_ cue: String, in before: Substring) -> Bool {
        guard let range = before.range(of: cue, options: .backwards) else { return false }
        let gap = before[range.upperBound...].split(whereSeparator: \.isWhitespace)
        return gap.count <= 2 // "starting on", "from the", "à partir du"
    }

    // MARK: Rules

    private struct Rule {
        var pattern: String
        var resolve: (NSTextCheckingResult, String, Date, Calendar) -> Date?
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, _ text: String) -> String? {
        guard index < match.numberOfRanges, let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    private static func rules(_ w: Words) -> [Rule] {
        let weekdays = w.weekdays.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let months = w.months.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let numbers = w.numbers.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let b = #"(?<![\p{L}])"#, e = #"(?![\p{L}])"#
        return [
            // "the day after tomorrow", "après-demain", "pasado mañana"
            Rule(pattern: b + "(?:\(w.dayAfterTomorrow.joined(separator: "|")))" + e) { _, _, said, calendar in
                calendar.date(byAdding: .day, value: 2, to: said)
            },
            Rule(pattern: b + "(?:\(w.tomorrow.joined(separator: "|")))" + e) { match, text, said, calendar in
                // Spanish "mañana" is also "morning": not after "la", "de la", "por la", "esta".
                if let range = Range(match.range, in: text) {
                    let before = text[..<range.lowerBound].suffix(6)
                    if w.morningGuards.contains(where: { before.hasSuffix($0) }) { return nil }
                }
                return calendar.date(byAdding: .day, value: 1, to: said)
            },
            Rule(pattern: b + "(?:\(w.today.joined(separator: "|")))" + e) { _, _, said, _ in said },
            // "end of the week", "end of next week", "fin de la semaine", "final de la semana"
            Rule(pattern: b + "(?:\(w.endOfWeek.joined(separator: "|")))" + e) { _, _, said, calendar in
                upcoming(weekday: 6, from: said, calendar: calendar, includingToday: true)
            },
            Rule(pattern: b + "(?:\(w.endOfNextWeek.joined(separator: "|")))" + e) { _, _, said, calendar in
                upcoming(weekday: 6, from: said, calendar: calendar, includingToday: true).flatMap { calendar.date(byAdding: .day, value: 7, to: $0) }
            },
            Rule(pattern: b + "(?:\(w.endOfMonth.joined(separator: "|")))" + e) { _, _, said, calendar in
                calendar.dateInterval(of: .month, for: said).flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) }
            },
            Rule(pattern: b + "(?:\(w.nextWeek.joined(separator: "|")))" + e) { _, _, said, calendar in
                // Monday of next week.
                upcoming(weekday: 2, from: said, calendar: calendar, includingToday: false)
            },
            // "in 3 days", "in two weeks", "dans 3 jours", "en dos semanas"
            Rule(pattern: b + "(?:\(w.inPrefix.joined(separator: "|"))) (\\d+|\(numbers)|\(w.a.joined(separator: "|"))) (\(w.dayWords.joined(separator: "|"))|\(w.weekWords.joined(separator: "|")))" + e) { match, text, said, calendar in
                guard let countText = group(match, 1, text), let unit = group(match, 2, text) else { return nil }
                let count = Int(countText) ?? w.numbers[countText] ?? (w.a.contains(countText) ? 1 : nil)
                guard let count else { return nil }
                return calendar.date(byAdding: .day, value: w.weekWords.contains(unit) ? count * 7 : count, to: said)
            },
            // "October 23rd", "Oct 23", "23 October", "23rd of October", "le 23 octobre", "el 23 de octubre"
            Rule(pattern: b + "(\(months))\\.? (\\d{1,2})(?:st|nd|rd|th)?" + e) { match, text, said, calendar in
                guard let month = group(match, 1, text).flatMap({ w.months[$0] }), let day = group(match, 2, text).flatMap(Int.init) else { return nil }
                return nextDate(month: month, day: day, after: said, calendar: calendar)
            },
            Rule(pattern: b + "(\\d{1,2})(?:st|nd|rd|th|er)? (?:of |de )?(\(months))" + e) { match, text, said, calendar in
                guard let day = group(match, 1, text).flatMap(Int.init), let month = group(match, 2, text).flatMap({ w.months[$0] }) else { return nil }
                return nextDate(month: month, day: day, after: said, calendar: calendar)
            },
            // "next Friday", "this Friday", "Friday", "vendredi prochain", "el próximo viernes"
            Rule(pattern: b + "(?:(\(w.next.isEmpty ? "(?!)" : w.next.joined(separator: "|"))) |(?:\(w.this.joined(separator: "|")) ))?(\(weekdays))(?: (\(w.nextAfter.joined(separator: "|"))))?" + e) { match, text, said, calendar in
                guard let name = group(match, 2, text), let weekday = w.weekdays[name],
                      var date = upcoming(weekday: weekday, from: said, calendar: calendar, includingToday: false)
                else { return nil }
                // "Next Friday" said early in the week means the one after this week's.
                if group(match, 1, text) != nil || group(match, 3, text) != nil,
                   calendar.isDate(date, equalTo: said, toGranularity: .weekOfYear) {
                    date = calendar.date(byAdding: .day, value: 7, to: date) ?? date
                }
                return date
            },
        ]
    }

    /// The next `weekday` (1 Sunday … 7 Saturday) after `date`, or that day itself if `includingToday`.
    static func upcoming(weekday: Int, from date: Date, calendar: Calendar, includingToday: Bool) -> Date? {
        let today = calendar.component(.weekday, from: date)
        var ahead = (weekday - today + 7) % 7
        if ahead == 0, !includingToday { ahead = 7 }
        return calendar.date(byAdding: .day, value: ahead, to: date)
    }

    /// That month and day, this year, or next year if it has already passed.
    static func nextDate(month: Int, day: Int, after date: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: date)
        guard var candidate = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: candidate) == day
        else { return nil }
        if candidate < calendar.startOfDay(for: date) {
            candidate = calendar.date(byAdding: .year, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }

    /// Date words per language. Other languages fall back to English.
    struct Words {
        var today: [String]
        var tomorrow: [String]
        var dayAfterTomorrow: [String]
        var morningGuards: [String] = []
        var nextWeek: [String]
        var endOfWeek: [String]
        var endOfNextWeek: [String]
        var endOfMonth: [String]
        var inPrefix: [String]
        var a: [String]
        var dayWords: [String]
        var weekWords: [String]
        var numbers: [String: Int]
        /// "next Friday" (a week further out when said early in the week) and "this Friday" (the coming one).
        var next: [String]
        var this: [String]
        var nextAfter: [String] = []
        var weekdays: [String: Int]
        var months: [String: Int]
        var startCues: [String]

        static func forLanguage(_ code: String) -> Words {
            switch code {
            case "fr": french
            case "es": spanish
            default: english
            }
        }

        static let english = Words(
            today: ["today", "tonight", "this evening", "end of day", "end of the day"],
            tomorrow: ["tomorrow"],
            dayAfterTomorrow: ["the day after tomorrow", "day after tomorrow"],
            nextWeek: ["next week"],
            endOfWeek: ["end of the week", "end of this week", "end of week"],
            endOfNextWeek: ["end of next week"],
            endOfMonth: ["end of the month", "end of this month", "end of month"],
            inPrefix: ["in", "within"],
            a: ["a", "one"],
            dayWords: ["days", "day"],
            weekWords: ["weeks", "week"],
            numbers: ["two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10],
            next: ["next"],
            this: ["this coming", "this", "coming", "on"],
            weekdays: ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7],
            months: [
                "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4, "may": 5,
                "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8, "september": 9, "sept": 9, "sep": 9,
                "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12,
            ],
            startCues: ["starting", "start", "starts", "beginning", "begin", "from", "kick off", "kicking off", "commencing", "as of"]
        )

        static let french = Words(
            today: ["aujourd'hui", "aujourd’hui", "ce soir"],
            tomorrow: ["demain"],
            dayAfterTomorrow: ["après-demain", "après demain"],
            nextWeek: ["la semaine prochaine"],
            endOfWeek: ["fin de la semaine", "fin de semaine", "fin de cette semaine"],
            endOfNextWeek: ["fin de la semaine prochaine"],
            endOfMonth: ["fin du mois", "fin de ce mois"],
            inPrefix: ["dans", "d'ici", "d’ici"],
            a: ["un", "une"],
            dayWords: ["jours", "jour"],
            weekWords: ["semaines", "semaine"],
            numbers: ["deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10, "quinze": 15],
            next: [],
            this: ["ce", "cette"],
            nextAfter: ["prochain", "prochaine"],
            weekdays: ["dimanche": 1, "lundi": 2, "mardi": 3, "mercredi": 4, "jeudi": 5, "vendredi": 6, "samedi": 7],
            months: [
                "janvier": 1, "février": 2, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6, "juillet": 7,
                "août": 8, "aout": 8, "septembre": 9, "octobre": 10, "novembre": 11, "décembre": 12, "decembre": 12,
            ],
            startCues: ["à partir de", "à partir du", "a partir de", "dès", "commencer", "commence", "débuter", "début"]
        )

        static let spanish = Words(
            today: ["hoy", "esta noche"],
            tomorrow: ["mañana"],
            dayAfterTomorrow: ["pasado mañana"],
            morningGuards: ["la ", "esta "],
            nextWeek: ["la semana que viene", "la próxima semana", "la semana próxima"],
            endOfWeek: ["final de la semana", "finales de la semana", "fin de la semana"],
            endOfNextWeek: ["final de la semana que viene", "final de la próxima semana"],
            endOfMonth: ["final de mes", "fin de mes", "final del mes", "fin del mes", "finales de mes"],
            inPrefix: ["en", "dentro de"],
            a: ["un", "una"],
            dayWords: ["días", "dias", "día", "dia"],
            weekWords: ["semanas", "semana"],
            numbers: ["dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10, "quince": 15],
            next: ["el próximo", "el proximo"],
            this: ["este", "el"],
            nextAfter: ["que viene", "próximo", "proximo"],
            weekdays: ["domingo": 1, "lunes": 2, "martes": 3, "miércoles": 4, "miercoles": 4, "jueves": 5, "viernes": 6, "sábado": 7, "sabado": 7],
            months: [
                "enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6, "julio": 7, "agosto": 8,
                "septiembre": 9, "setiembre": 9, "octubre": 10, "noviembre": 11, "diciembre": 12,
            ],
            startCues: ["a partir del", "a partir de", "desde el", "desde", "empezar", "empieza", "empezando", "comenzar", "comienza"]
        )
    }
}
