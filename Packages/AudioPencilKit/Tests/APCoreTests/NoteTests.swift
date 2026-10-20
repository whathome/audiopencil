import APCore
import Foundation
import Testing

struct NoteTests {
    private let toronto = TimeZone(identifier: "America/Toronto")!

    private func note(title: String = "Backup plan for the home server", style: String = "professional") -> Note {
        Note(
            title: title, styleID: style, status: .needsReview,
            recorded: ISO8601DateFormatter().date(from: "2026-10-19T18:30:05Z")!,
            duration: 312.4, mode: .longForm, tags: ["home-lab", "backups"], folder: "/Work/Notes",
            audioPath: "/Audio Pencil/Recordings/2026-10-19 1430 Backup plan for the home server.m4a",
            body: "Summary paragraph.\n\n- Point one", transcript: "So I've been thinking.\n\nAbout backups."
        )
    }

    @Test func fileNameFollowsThePRDRule() {
        #expect(NoteRenderer.baseName(for: note(), timeZone: toronto) == "2026-10-19 1430 Backup plan for the home server")
        #expect(NoteRenderer.notePath(for: note(), timeZone: toronto) == "/Work/Notes/2026-10-19 1430 Backup plan for the home server.md")
    }

    @Test func titlesAreMadeSafeForFilesAndLinks() {
        #expect(NoteRenderer.safeTitle("Q3: plan / #budget [draft]?") == "Q3 plan budget draft")
        #expect(NoteRenderer.safeTitle("  trailing dots... ") == "trailing dots")
        let long = NoteRenderer.safeTitle(String(repeating: "word ", count: 30))
        #expect(long.count <= 60 && !long.hasSuffix(" "))
        #expect(NoteRenderer.fallbackTitle(from: "So, I've been thinking about the backup situation lately.") == "So, I've been thinking about the backup")
    }

    @Test func markdownHasFrontmatterAudioAndCollapsedTranscript() {
        let markdown = NoteRenderer.markdown(for: note(), timeZone: toronto)
        #expect(markdown.hasPrefix("---\ntype: audio-pencil\nstyle: professional\nstatus: needs-review\nrecorded: 2026-10-19T14:30:05-04:00\nduration: 312\ndevice: mac\nmode: long-form\nlanguage: en\nretention: regular\ntags:\n  - home-lab\n  - backups\n"))
        #expect(markdown.contains("audio: \"[[Audio Pencil/Recordings/2026-10-19 1430 Backup plan for the home server.m4a]]\"\n---"))
        #expect(markdown.contains("\n![[Audio Pencil/Recordings/2026-10-19 1430 Backup plan for the home server.m4a]]\n"))
        #expect(markdown.contains("> [!quote]- Transcript\n> So I've been thinking.\n>\n> About backups.\n"))
    }

    @Test func quickRawNoteIsMinimal() {
        var quick = note(style: "raw")
        quick.mode = .quick
        quick.audioPath = nil
        quick.transcript = nil
        quick.tags = []
        let markdown = NoteRenderer.markdown(for: quick, timeZone: toronto)
        #expect(markdown.contains("tags: []\n---\n\nSummary paragraph."))
        #expect(!markdown.contains("audio:"))
        #expect(!markdown.contains("[!quote]"))
    }
}

struct LongFormPromptTests {
    @Test func sectionsSplitAtSentencesUnderTheLimit() {
        let sentence = "This is one sentence with eight words in it. "
        let transcript = String(repeating: sentence, count: 600) // 5,400 words
        let sections = PromptBuilder.sections(of: transcript, limit: 2_000)
        #expect(sections.count == 3)
        #expect(sections.allSatisfy { UsageStats.wordCount($0) <= 2_000 })
        #expect(sections.allSatisfy { $0.hasSuffix(".") })
        #expect(sections.map(UsageStats.wordCount).reduce(0, +) == UsageStats.wordCount(transcript)) // nothing dropped
    }

    @Test func shortTranscriptIsOneSection() {
        #expect(PromptBuilder.sections(of: "Just a short note. Nothing more.") == ["Just a short note. Nothing more."])
    }

    @Test func parsesTitleAndTagsLeniently() {
        let answer = "Sure! Here you go:\nTitle: \"Backup plan for the home server\"\nTags: #Home Lab, backups, Backups, nextcloud, extra, fifth"
        let parsed = TitleAndTags.parse(answer)
        #expect(parsed.title == "Backup plan for the home server")
        #expect(parsed.tags == ["home-lab", "backups", "nextcloud", "extra"])
        #expect(TitleAndTags.parse("nonsense").title == nil)
    }

    @Test func titlePromptPrefersKnownTags() {
        let prompt = PromptBuilder.titleAndTagsPrompt(text: "words", knownTags: ["work", "diary"])
        #expect(prompt.instructions.contains("preferably from this list: work, diary"))
    }
}
