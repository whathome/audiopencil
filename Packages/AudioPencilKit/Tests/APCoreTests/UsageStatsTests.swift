import APCore
import Foundation
import Testing

struct UsageStatsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        calendar.firstWeekday = 1 // Sunday
        return calendar
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    @Test func totalsAndDerivedNumbers() {
        var stats = UsageStats()
        stats.record(words: 100, audioSeconds: 60, on: day(2026, 10, 19), calendar: calendar)
        stats.record(words: 100, audioSeconds: 60, on: day(2026, 10, 19), calendar: calendar)
        #expect(stats.dictations == 2)
        #expect(stats.words == 200)
        #expect(stats.talkingWordsPerMinute == 100)
        // 200 words at 40 wpm = 5 min of typing, minus 2 min of talking.
        #expect(stats.timeSaved() == 180)
    }

    @Test func talkingSpeedNeedsEnoughAudio() {
        var stats = UsageStats()
        stats.record(words: 10, audioSeconds: 5)
        #expect(stats.talkingWordsPerMinute == nil)
    }

    @Test func recentDaysAlignToWeeksAndCountPerDay() {
        var stats = UsageStats()
        stats.record(words: 5, audioSeconds: 3, on: day(2026, 10, 19, hour: 8), calendar: calendar)
        stats.record(words: 5, audioSeconds: 3, on: day(2026, 10, 19, hour: 23), calendar: calendar)
        stats.record(words: 5, audioSeconds: 3, on: day(2026, 10, 12), calendar: calendar)
        let days = stats.recentDays(weeks: 5, endingOn: day(2026, 10, 19), calendar: calendar)
        #expect(days.count == 35)
        #expect(calendar.component(.weekday, from: days[0].date) == 1) // starts on a Sunday
        #expect(days.first { calendar.isDate($0.date, inSameDayAs: day(2026, 10, 19)) }?.count == 2)
        #expect(days.first { calendar.isDate($0.date, inSameDayAs: day(2026, 10, 12)) }?.count == 1)
        #expect(days.reduce(0) { $0 + $1.count } == 3)
        #expect(stats.activeDaysThisMonth(now: day(2026, 10, 19), calendar: calendar) == 2)
    }

    @Test func countsWords() {
        #expect(UsageStats.wordCount("Lunch is at noon,\ntomorrow.") == 5)
    }
}
