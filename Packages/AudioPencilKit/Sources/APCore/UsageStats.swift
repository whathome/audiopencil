import Foundation

/// Running totals for the stats panel. Counts only: no text, no audio, no app names.
public struct UsageStats: Codable, Equatable, Sendable {
    public private(set) var dictations = 0
    public private(set) var words = 0
    public private(set) var audioSeconds: Double = 0
    /// Dictations per local calendar day, keyed "yyyy-MM-dd".
    public private(set) var perDay: [String: Int] = [:]

    public init() {}

    public mutating func record(words: Int, audioSeconds: Double, on date: Date = Date(), calendar: Calendar = .current) {
        dictations += 1
        self.words += words
        self.audioSeconds += audioSeconds
        perDay[Self.key(for: date, calendar: calendar), default: 0] += 1
    }

    /// Typing time the dictated words would have taken, minus the time spent talking.
    public func timeSaved(typingWordsPerMinute: Double = 40) -> TimeInterval {
        max(0, Double(words) / typingWordsPerMinute * 60 - audioSeconds)
    }

    /// Words per minute of recorded audio; nil until there's enough to be meaningful.
    public var talkingWordsPerMinute: Int? {
        guard audioSeconds >= 30 else { return nil }
        return Int((Double(words) / (audioSeconds / 60)).rounded())
    }

    /// Dictation counts for the last `weeks` whole weeks up to today, oldest first,
    /// starting on the calendar's first weekday so rows line up as weeks.
    public func recentDays(weeks: Int = 5, endingOn today: Date = Date(), calendar: Calendar = .current) -> [(date: Date, count: Int)] {
        let startOfToday = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: startOfToday)
        let daysIntoWeek = (weekday - calendar.firstWeekday + 7) % 7
        guard let firstDay = calendar.date(byAdding: .day, value: -(daysIntoWeek + 7 * (weeks - 1)), to: startOfToday) else { return [] }
        return (0..<(weeks * 7)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            return (day, day > startOfToday ? 0 : perDay[Self.key(for: day, calendar: calendar)] ?? 0)
        }
    }

    /// Number of distinct days with at least one dictation in the current month.
    public func activeDaysThisMonth(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let month = calendar.dateComponents([.year, .month], from: now)
        return perDay.keys.filter { key in
            guard let date = Self.date(from: key, calendar: calendar) else { return false }
            return calendar.dateComponents([.year, .month], from: date) == month
        }.count
    }

    public static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func date(from key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
