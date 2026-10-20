import APCore
import APStorage
import Foundation
import Yams

/// First-run files in the vault (PRD "Bases file created by the app", "First run"): the review board,
/// a guide note, and sample notes so the board shows real cards straight away.
public enum StarterKit {
    public static let basePath = "/Audio Pencil/Audio Pencil.base"
    public static let guidePath = "/Audio Pencil/Audio Pencil guide.md"
    public static let samplesFolder = "/Audio Pencil/Samples"

    /// Obsidian Bases file: Kanban of professional notes by status, a diary list, everything, and retention.
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
          note.retention:
            displayName: Keep
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
          - type: kanban
            name: Retention
            groupBy:
              property: note.retention
              direction: ASC
            groupOrder:
              - regular
              - archive
              - delete
            order:
              - file.name
              - note.recorded
              - note.style

        """

    /// Earlier versions of `base`, exactly as shipped. A board still matching one of these is upgraded;
    /// a board the user has edited is left alone.
    static let previousBases: [String] = [
        """
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

        """,
    ]

    static let englishGuide = """
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
        - **Retention**: what to keep. *regular* notes keep their audio for a year, then the audio is removed \
        (the note stays). *archive* keeps note and audio forever. Drag a card to *delete* and Audio Pencil \
        deletes the note and its audio (to the trash) the next time it checks.

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
        | `language` | The language spoken, for example `en`. |
        | `tags` | From your tag list in `Audio Pencil/Settings.md`. |
        | `retention` | `regular` (audio kept a year), `archive` (kept forever) or `delete` (removed next check). |
        | `audio` | Link to the recording in `Audio Pencil/Recordings` (long recordings only). |

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

    /// Sample notes, in the interface language. Fixed content, recorded "now" so they show up at the top
    /// of the board.
    public static func samples(now: Date = Date(), device: String = "mac") -> [Note] {
        let text = SampleText.current
        let diary = Note(
            title: text.diaryTitle, styleID: "diary", status: .reviewed,
            recorded: now.addingTimeInterval(-3 * 86_400), duration: 74, device: device, mode: .longForm,
            tags: ["sample"], folder: samplesFolder, language: text.language,
            body: text.diaryBody
        )
        let professional = Note(
            title: text.professionalTitle, styleID: "professional", status: .reviewed,
            recorded: now.addingTimeInterval(-2 * 86_400), duration: 141, device: device, mode: .longForm,
            tags: ["sample"], folder: samplesFolder, language: text.language,
            body: text.professionalBody,
            transcript: text.professionalTranscript
        )
        let needsReview = Note(
            title: text.reviewTitle, styleID: "professional", status: .needsReview,
            recorded: now.addingTimeInterval(-3_600), duration: 392, device: device, mode: .longForm,
            tags: ["sample"], folder: samplesFolder, language: text.language,
            body: text.reviewBody,
            transcript: text.reviewTranscript
        )
        return [diary, professional, needsReview]
    }

    public enum Outcome: Equatable, Sendable {
        case alreadyThere
        /// The board was edited by hand, so new views weren't added.
        case boardCustomised
        case created(files: [String])
    }

    /// Creates the board and guide if missing; samples only when `includeSamples` (first run for this vault).
    /// Never overwrites anything.
    public static func ensure(in provider: any StorageProvider, vaultPath: String, includeSamples: Bool, now: Date = Date(), timeZone: TimeZone = .current) async throws -> Outcome {
        var created: [String] = []
        var boardCustomised = false
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
        let board = StoragePath.join(vaultPath, basePath)
        if !created.contains(basePath), let (data, etag) = try? await provider.read(board) {
            let current = String(decoding: data, as: UTF8.self)
            if previousBases.contains(current) {
                try await provider.write(board, data: Data(base.utf8), ifMatch: etag, createOnly: false)
                created.append(basePath)
            } else if current != base {
                boardCustomised = true
            }
        }
        try await create(guidePath, guide)
        if includeSamples {
            for note in samples(now: now) {
                try await create(NoteRenderer.notePath(for: note, timeZone: timeZone), NoteRenderer.markdown(for: note, timeZone: timeZone))
            }
        }
        if boardCustomised, created.isEmpty { return .boardCustomised }
        return created.isEmpty ? .alreadyThere : .created(files: created)
    }
}

// MARK: Keeping the board working

extension StarterKit {
    public enum BoardCheck: Equatable, Sendable {
        case ok
        case created
        /// Views the app relies on were missing and have been added back.
        case addedViews([String])
        /// The file doesn't parse (perhaps mid-edit). Left alone; `repairBoard` fixes it on request.
        case unparseable(String)
    }

    /// The views the app depends on (taken from `base`).
    static var requiredViews: [Node] {
        (try? Yams.compose(yaml: base))?["views"]?.sequence.map(Array.init) ?? []
    }

    public static var requiredViewNames: [String] { requiredViews.compactMap { $0["name"]?.string } }

    /// Makes sure the board exists and still has every required view (matched by name).
    /// Anything else in the file (your own views, filters, formulas, view settings) is kept.
    public static func ensureBoard(in provider: any StorageProvider, vaultPath: String) async throws -> BoardCheck {
        let path = StoragePath.join(vaultPath, basePath)
        guard try await provider.item(at: path) != nil else {
            try await provider.createFolder(StoragePath.parent(of: path))
            try await provider.write(path, data: Data(base.utf8), ifMatch: nil, createOnly: true)
            return .created
        }
        let (data, etag) = try await provider.read(path)
        let text = String(decoding: data, as: UTF8.self)
        let root: Node
        do {
            guard let parsed = try Yams.compose(yaml: text), parsed.mapping != nil else { return .unparseable("The board isn't a YAML mapping.") }
            root = parsed
        } catch {
            return .unparseable(String(describing: error))
        }
        let (fixed, added) = try addingMissingViews(to: root)
        guard !added.isEmpty else { return .ok }
        try await provider.write(path, data: Data(try Yams.serialize(node: fixed).utf8), ifMatch: etag, createOnly: false)
        return .addedViews(added)
    }

    static func addingMissingViews(to root: Node) throws -> (Node, [String]) {
        let existing = root["views"]?.sequence.map(Array.init) ?? []
        let names = Set(existing.compactMap { $0["name"]?.string })
        let missing = requiredViews.filter { !names.contains($0["name"]?.string ?? "") }
        guard !missing.isEmpty else { return (root, []) }
        var fixed = root
        fixed["views"] = Node(existing + missing)
        return (fixed, missing.compactMap { $0["name"]?.string })
    }

    public struct BoardRepair: Equatable, Sendable {
        public var keptViews: [String]
        public var droppedSections: Int
        public var backupPath: String
    }

    /// For a board that won't parse: keeps every top-level section and view that still parses,
    /// re-adds the required views, and saves the broken original as a backup note first.
    public static func repairBoard(in provider: any StorageProvider, vaultPath: String, now: Date = Date()) async throws -> BoardRepair {
        let path = StoragePath.join(vaultPath, basePath)
        let (data, etag) = try await provider.read(path)
        let broken = String(decoding: data, as: UTF8.self)

        var keptViews: [Node] = []
        var keptSections: [(Node, Node)] = []
        var dropped = 0
        for (key, chunk) in YAMLSalvage.topLevelChunks(broken) {
            if key == "views" {
                for item in YAMLSalvage.sequenceItems(chunk) {
                    if let node = (try? Yams.compose(yaml: item))?.sequence?.first, node.mapping != nil {
                        keptViews.append(node)
                    } else {
                        dropped += 1
                    }
                }
            } else if let node = try? Yams.compose(yaml: chunk), let pair = node.mapping?.first {
                keptSections.append((pair.key, pair.value))
            } else {
                dropped += 1
            }
        }
        if !keptSections.contains(where: { $0.0.string == "filters" }), let filters = (try? Yams.compose(yaml: base))?["filters"] {
            keptSections.insert((Node("filters"), filters), at: 0)
        }
        let rebuilt = Node(keptSections + [(Node("views"), Node(keptViews))])
        let (fixed, _) = try addingMissingViews(to: rebuilt)

        let backup = try await saveBackup(of: broken, name: "Audio Pencil board", asYAML: true, provider: provider, vaultPath: vaultPath, now: now)
        try await provider.write(path, data: Data(try Yams.serialize(node: fixed).utf8), ifMatch: etag, createOnly: false)
        return BoardRepair(keptViews: keptViews.compactMap { $0["name"]?.string }, droppedSections: dropped, backupPath: backup)
    }

    /// Saves a broken file's text as a note in "Audio Pencil/Backups" before it's repaired.
    static func saveBackup(of text: String, name: String, asYAML: Bool, provider: any StorageProvider, vaultPath: String, now: Date) async throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let folder = StoragePath.join(vaultPath, "Audio Pencil", "Backups")
        try await provider.createFolder(folder)
        let body = asYAML ? "Broken copy saved before Audio Pencil repaired it.\n\n```yaml\n\(text)\n```\n" : text
        for attempt in 1...20 {
            let file = "\(name) (broken copy \(formatter.string(from: now)))" + (attempt == 1 ? "" : "-\(attempt)") + ".md"
            let path = StoragePath.join(folder, file)
            do {
                try await provider.write(path, data: Data(body.utf8), ifMatch: nil, createOnly: true)
                return path
            } catch StorageError.conflict {
                continue
            }
        }
        throw StorageError.conflict(folder)
    }
}
