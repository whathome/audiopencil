import APSync
import Foundation
import Testing

struct DailyNotesTests {
    /// Wednesday 21 October 2026, 14:32.
    private let date = ISO8601DateFormatter().date(from: "2026-10-21T14:32:05Z")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func detectsThePluginInBothFormats() {
        #expect(DailyNotesSetup.isEnabled(corePlugins: Data(#"{"file-explorer": true, "daily-notes": true}"#.utf8)))
        #expect(!DailyNotesSetup.isEnabled(corePlugins: Data(#"{"daily-notes": false}"#.utf8)))
        #expect(DailyNotesSetup.isEnabled(corePlugins: Data(#"["file-explorer", "daily-notes"]"#.utf8)))
        #expect(!DailyNotesSetup.isEnabled(corePlugins: Data("not json".utf8)))
    }

    @Test func pathsFollowFolderAndFormat() {
        #expect(DailyNotesSetup.settings(nil).path(for: date, calendar: calendar) == "/2026-10-21.md")
        let custom = DailyNotesSetup.settings(Data(#"{"folder": "Journal", "format": "YYYY/MM/YYYY-MM-DD dddd", "template": "Templates/Daily"}"#.utf8))
        #expect(custom.path(for: date, calendar: calendar) == "/Journal/2026/10/2026-10-21 Wednesday.md")
        #expect(custom.templatePath == "/Templates/Daily.md")
        #expect(DailyNotesSetup(format: "[Day] Do MMM YY").path(for: date, calendar: calendar) == "/Day 21st Oct 26.md")
    }

    @Test func templatesFillObsidianVariables() {
        let template = "# {{title}}\nCreated {{date}} at {{time}} ({{date:dddd, MMMM Do}})\n"
        #expect(DailyTemplate.fill(template, title: "2026-10-21", date: date, calendar: calendar)
            == "# 2026-10-21\nCreated 2026-10-21 at 14:32 (Wednesday, October 21st)\n")
    }

    @Test func appendsAtTheEndOrUnderAHeading() {
        #expect(NoteAppend.apply("- 14:32 hi", to: "", heading: nil) == "- 14:32 hi\n")
        #expect(NoteAppend.apply("- 14:32 hi", to: "Notes so far", heading: "") == "Notes so far\n- 14:32 hi\n")
        // A new section goes at the end.
        #expect(NoteAppend.apply("- a", to: "# Wednesday\nPlans.\n", heading: "## Audio Pencil") == "# Wednesday\nPlans.\n\n## Audio Pencil\n- a\n")
        // An existing section gets the line after its last entry, before the next heading.
        let note = "## Audio Pencil\n- first\n\n## Tasks\n- [ ] thing\n"
        #expect(NoteAppend.apply("- second", to: note, heading: "## Audio Pencil") == "## Audio Pencil\n- first\n- second\n\n## Tasks\n- [ ] thing\n")
        // A deeper heading inside the section doesn't end it.
        let nested = "## Audio Pencil\n- first\n### Detail\n- x\n## Other\n"
        #expect(NoteAppend.apply("- second", to: nested, heading: "## Audio Pencil") == "## Audio Pencil\n- first\n### Detail\n- x\n- second\n## Other\n")
    }
}
