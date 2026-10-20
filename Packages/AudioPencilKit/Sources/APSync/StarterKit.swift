import APCore
import APStorage
import Foundation

/// First-run files in the vault (PRD "Bases file created by the app", "First run"): the review board,
/// a guide note, and sample notes so the board shows real cards straight away.
public enum StarterKit {
    public static let basePath = "/Audio Pencil/Audio Pencil.base"
    public static let guidePath = "/Audio Pencil/Audio Pencil guide.md"
    public static let samplesFolder = "/Audio Pencil/Samples"

    /// Obsidian Bases file: Kanban of professional notes by status, a diary list, and everything.
    public static let base = """
        filters:
          and:
            - 'type == "audio-pencil"'
        properties:
          note.status:
            displayName: Status
          note.style:
            displayName: Style
          note.recorded:
            displayName: Recorded
          note.duration:
            displayName: Seconds
        views:
          - type: kanban
            name: Professional review
            filters:
              and:
                - 'style == "professional"'
            groupBy:
              property: note.status
              direction: ASC
            groupOrder:
              - needs-review
              - reviewed
              - actioned
            order:
              - file.name
              - note.recorded
              - note.tags
          - type: table
            name: Diary
            filters:
              and:
                - 'style == "diary"'
            order:
              - file.name
              - note.recorded
              - note.duration
            sort:
              - property: note.recorded
                direction: DESC
          - type: table
            name: All recordings
            order:
              - file.name
              - note.style
              - note.status
              - note.mode
              - note.recorded
              - note.duration
              - note.tags
            sort:
              - property: note.recorded
                direction: DESC

        """

    public static let guide = """
        ---
        type: audio-pencil-guide
        tags:
          - sample
        ---

        # Audio Pencil guide

        Audio Pencil writes every saved recording as a note with the same **properties** (the block at the top \
        of each note). Obsidian's Bases turn those properties into a review board, so there's nothing to file \
        by hand.

        ## The board

        Open [[Audio Pencil/Audio Pencil.base|Audio Pencil.base]]. It has three views (switch at the top left):

        - **Professional review**: a Kanban board of Professional notes, one column per `status`. Drag a card \
        from *needs-review* to *reviewed* once you've read it, and to *actioned* when its action items are done. \
        Dragging changes the note's `status` property for you.
        - **Diary**: your diary entries, newest first.
        - **All recordings**: everything, as a table you can sort and filter.

        ## The properties

        | Property | What it means |
        | --- | --- |
        | `type` | Always `audio-pencil`, so the board finds these notes. |
        | `style` | How the recording was written up: `raw`, `polished`, `diary`, `professional`, or your own styles. |
        | `status` | `needs-review` (new or skipped), `reviewed`, or `actioned`. |
        | `recorded` | When you started talking. |
        | `duration` | Length of the recording in seconds. |
        | `device` | `mac` or `iphone`. |
        | `mode` | `quick` (hotkey dictation), `long-form`, or `meeting`. |
        | `tags` | From your tag list in `Audio Pencil/Settings.md`. |
        | `audio` | Link to the recording in `Audio Pencil/Recordings` (long recordings only; kept for a year). |

        ## Statuses in practice

        - When a long recording finishes, Audio Pencil asks you to approve its title, tags and folder. \
        **Approve** saves it as `reviewed`; **Skip** saves it as `needs-review`, so it waits on the board.
        - Work through the *needs-review* column when you have a moment; nothing gets lost.
        - Use *actioned* for Professional notes whose action items you've done.

        ## Worked examples

        The notes in [[Audio Pencil/Samples]] are examples (tagged `sample`, safe to delete):

        - a Diary entry: your words, tidied;
        - a Professional note with action items and the original transcript folded underneath;
        - a note still in *needs-review*.

        ## Settings

        Styles, vocabulary and the tag list live in [[Audio Pencil/Settings|Settings]]. Edit them there or in \
        the app; both stay in step.

        """

    /// Sample notes. Fixed content, recorded "now" so they show up at the top of the board.
    public static func samples(now: Date = Date(), device: String = "mac") -> [Note] {
        let diary = Note(
            title: "Sample: a good day with a run along the river", styleID: "diary", status: .reviewed,
            recorded: now.addingTimeInterval(-3 * 86_400), duration: 74, device: device, mode: .longForm,
            tags: ["sample"], folder: samplesFolder,
            body: """
                Today was actually a pretty good day. I got up early and went for a run along the river, which I \
                hadn't done in two weeks, and it felt really good.

                Work was mostly meetings. The server migration finally finished, so that's a weight off. In the \
                afternoon I picked up the kids and we made pizza, and Maya put way too much cheese on hers, which \
                was funny.

                I'm a bit tired now, but in a good way. I want to keep the running going, maybe three times a week.
                """
        )
        let professional = Note(
            title: "Sample: backup plan for the home server", styleID: "professional", status: .reviewed,
            recorded: now.addingTimeInterval(-2 * 86_400), duration: 141, device: device, mode: .longForm,
            tags: ["sample"], folder: samplesFolder,
            body: """
                The home server is backed up nightly to a drive in the same room, which won't survive a fire. \
                I'm choosing between a drive swapped at my parents' place, encrypted backups to the Nextcloud box \
                at the cottage, or paid cloud storage, and leaning towards the cottage because it's automatic.

                **Key points**
                - Current backups share a room with the server: no protection from fire or theft.
                - Cottage upload is about 10 Mbps, so the first sync could take a week.
                - I've never tested a restore.

                **Action items**
                - [ ] Set up the cottage sync this weekend.
                - [ ] Ask Dave whether the cottage router can have a static IP.
                - [ ] Test-restore the photos folder next week.
                """,
            transcript: """
                So I've been thinking about the backup situation for the home server. Right now everything goes to, \
                uh, the external drive every night, and that's fine, but it's in the same room, so if there's a fire \
                or whatever, it's all gone. I'm leaning towards the cottage because it's automatic, but the upload \
                there is slow, like ten megabits, so the first sync would take, I don't know, a week maybe. I should \
                test restoring too, I've never actually restored anything, which is bad.
                """
        )
        let needsReview = Note(
            title: "Sample: ideas for the quarterly planning", styleID: "professional", status: .needsReview,
            recorded: now.addingTimeInterval(-3_600), duration: 392, device: device, mode: .longForm,
            tags: ["sample"], folder: samplesFolder,
            body: """
                For the quarter we should focus on three things: finishing the backup migration, shipping the new \
                onboarding flow, and hiring a second support person before the summer.

                **Key points**
                - Backup migration is the risk to clear first.
                - Onboarding changes depend on the new sign-up page.
                - Support load justifies a second hire.
                """,
            transcript: "So for the quarterly planning, I think we should focus on three things…"
        )
        return [diary, professional, needsReview]
    }

    public enum Outcome: Equatable, Sendable {
        case alreadyThere
        case created(files: [String])
    }

    /// Creates the board and guide if missing; samples only when `includeSamples` (first run for this vault).
    /// Never overwrites anything.
    public static func ensure(in provider: any StorageProvider, vaultPath: String, includeSamples: Bool, now: Date = Date(), timeZone: TimeZone = .current) async throws -> Outcome {
        var created: [String] = []
        func create(_ relative: String, _ text: String) async throws {
            let path = StoragePath.join(vaultPath, relative)
            if try await provider.item(at: path) != nil { return }
            try await provider.createFolder(StoragePath.parent(of: path))
            do {
                try await provider.write(path, data: Data(text.utf8), ifMatch: nil, createOnly: true)
                created.append(relative)
            } catch StorageError.conflict {
                // Created elsewhere in the meantime: leave it.
            }
        }
        try await create(basePath, base)
        try await create(guidePath, guide)
        if includeSamples {
            for note in samples(now: now) {
                try await create(NoteRenderer.notePath(for: note, timeZone: timeZone), NoteRenderer.markdown(for: note, timeZone: timeZone))
            }
        }
        return created.isEmpty ? .alreadyThere : .created(files: created)
    }
}
