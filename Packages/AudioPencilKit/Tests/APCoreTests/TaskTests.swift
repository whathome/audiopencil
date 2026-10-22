import APCore
import Foundation
import Testing

struct TaskTests {
    /// Tuesday 20 October 2026, mid-morning.
    private let said = ISO8601DateFormatter().date(from: "2026-10-20T14:00:00Z")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func dates(_ text: String, _ language: String = "en") -> (due: String?, start: String?) {
        let found = TaskDates.find(in: text, said: said, language: language, calendar: calendar)
        let format = { (date: Date?) in date.map { ISO8601DateFormatter.string(from: $0, timeZone: calendar.timeZone, formatOptions: [.withFullDate]) } }
        return (format(found.due), format(found.start))
    }

    @Test func relativeDaysCountFromWhenItWasSaid() {
        #expect(dates("Send the lease by Friday").due == "2026-10-23")
        #expect(dates("Call Sam tomorrow").due == "2026-10-21")
        #expect(dates("Finish the draft today").due == "2026-10-20")
        #expect(dates("Book flights the day after tomorrow").due == "2026-10-22")
        #expect(dates("Review it in two weeks").due == "2026-11-03")
        #expect(dates("Wrap up by the end of the month").due == "2026-10-31")
        #expect(dates("Ship it by end of next week").due == "2026-10-30")
        // Said on a Tuesday, "next Friday" is the one after this week's; "this Friday" is the coming one.
        #expect(dates("Send it next Friday").due == "2026-10-30")
        #expect(dates("Send it this Friday").due == "2026-10-23")
        // A weekday already past this week is next week's.
        #expect(dates("Pay rent Monday").due == "2026-10-26")
    }

    @Test func calendarDatesRollToNextYearOncePast() {
        #expect(dates("Renew the passport by November 3rd").due == "2026-11-03")
        #expect(dates("Taxes due 15th of April").due == "2027-04-15")
        #expect(dates("Party on Oct 31").due == "2026-10-31")
    }

    @Test func startCuesMakeStartDates() {
        let both = dates("Starting next Monday, prepare the report and send it by Friday")
        #expect(both.start == "2026-10-26")
        #expect(both.due == "2026-10-23")
        #expect(dates("Begin the audit from November 2").start == "2026-11-02")
        // "from" far from the date isn't a start cue.
        #expect(dates("Get the keys from the office by Thursday").start == nil)
        #expect(dates("Get the keys from the office by Thursday").due == "2026-10-22")
        #expect(dates("Buy milk") == (nil, nil))
    }

    @Test func frenchAndSpanishDates() {
        #expect(dates("Envoyer le bail avant vendredi", "fr").due == "2026-10-23")
        #expect(dates("Appeler Paul demain", "fr").due == "2026-10-21")
        #expect(dates("Rendre le rapport le 3 novembre", "fr").due == "2026-11-03")
        #expect(dates("À partir de lundi prochain, préparer le budget", "fr").start == "2026-10-26")
        #expect(dates("Enviar el contrato antes del viernes", "es").due == "2026-10-23")
        #expect(dates("Llamar a Ana mañana", "es").due == "2026-10-21")
        #expect(dates("Revisar el correo por la mañana", "es").due == nil) // morning, not tomorrow
        #expect(dates("Entregar el informe el 3 de noviembre", "es").due == "2026-11-03")
    }

    @Test func taskLinesUseTheTasksPluginFormat() {
        #expect(TaskLine.make("Send the lease by Friday", said: said, calendar: calendar) == "- [ ] Send the lease by Friday 📅 2026-10-23")
        #expect(TaskLine.make("- Buy milk", said: said, calendar: calendar) == "- [ ] Buy milk")
        #expect(TaskLine.make("Starting Monday,\nwalk daily until Friday", said: said, calendar: calendar)
            == "- [ ] Starting Monday, walk daily until Friday 🛫 2026-10-26 📅 2026-10-23")
    }

    @Test func actionItemSectionsBecomeTasks() {
        let note = """
            **Summary**: We agreed the budget.

            **Key points**
            - Rent under 4,000 a month

            **Action items**
            - Speaker 2: send the lease to the landlord by Friday
            - Speaker 1: review the floor plan
            1. Book movers next week

            Thanks all.
            """
        let tasks = ActionItems.asTasks(note, said: said, calendar: calendar)
        #expect(tasks.contains("- Rent under 4,000 a month")) // other lists stay as written
        #expect(tasks.contains("- [ ] Speaker 2: send the lease to the landlord by Friday 📅 2026-10-23"))
        #expect(tasks.contains("- [ ] Speaker 1: review the floor plan\n"))
        #expect(tasks.contains("- [ ] Book movers next week 📅 2026-10-26"))
        #expect(tasks.hasSuffix("Thanks all."))
        // "None" stays plain text; a French heading counts.
        #expect(ActionItems.asTasks("**Action items**: \n- None", said: said) == "**Action items**: \nNone")
        #expect(ActionItems.asTasks("**Actions à mener**\n- Appeler Paul demain", said: said, language: "fr", calendar: calendar)
            == "**Actions à mener**\n- [ ] Appeler Paul demain 📅 2026-10-21")
    }

    @Test func keywordsTurnDictationsIntoTasks() {
        let keywords = TaskKeywords.defaults
        #expect(TaskKeywords.remainder(of: "New task: call the landlord.", keywords: keywords) == "Call the landlord.")
        #expect(TaskKeywords.remainder(of: "new task, buy milk", keywords: keywords) == "Buy milk")
        #expect(TaskKeywords.remainder(of: "To-do pick up the dry cleaning", keywords: keywords) == "Pick up the dry cleaning")
        #expect(TaskKeywords.remainder(of: "Action item. Send the deck", keywords: keywords) == "Send the deck")
        #expect(TaskKeywords.remainder(of: "Nouvelle tâche : appeler Paul", keywords: ["nouvelle tache"]) == "Appeler Paul")
        #expect(TaskKeywords.remainder(of: "The new task is done", keywords: keywords) == nil) // only at the start
        #expect(TaskKeywords.remainder(of: "Today we shipped", keywords: ["to do"]) == nil) // whole words only
        #expect(TaskKeywords.remainder(of: "New task.", keywords: keywords) == nil) // nothing after it
    }
}
