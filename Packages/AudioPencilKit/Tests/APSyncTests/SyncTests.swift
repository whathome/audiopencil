import APCore
import APStorage
@testable import APSync
import Foundation
import Testing
import Yams
import os

private func sampleConfig() -> SharedConfig {
    var config = SharedConfig()
    config.vocabulary = ["Nextcloud", "WebDAV", "Wes's server: \"home\""]
    config.tags = ["work", "diary"]
    var custom = ConfigStyle(.polished)
    custom.id = "custom-1"
    custom.name = "Email: short & sweet"
    custom.instructions = "Line one: keep it short.\n\n  Indented line with \"quotes\" and # hash.\nLast line"
    config.styles = Style.presets.map(ConfigStyle.init) + [custom]
    var device = DeviceSection()
    device.microphones = [.init(name: "MacBook Air Microphone", uid: "BuiltInMicrophoneDevice")]
    device.languages = ["en", "fr", "no"]
    device.multilingualModel = "openai_whisper-small"
    config.devices = ["Wes’s MacBook Air": device, "iPhone": DeviceSection()]
    config.writingSamples = [
        WritingSample(id: "s1", kind: "diary", text: "Today: fine.\n\nSecond paragraph, with \"quotes\".", promptID: "diary"),
        WritingSample(id: "s2", kind: "work-email", text: "Bonjour, le projet a du retard.", language: "fr"),
    ]
    config.languageVocabulary = ["fr": ["Loïc-William", "Marie-Diane"], "no": ["Bjørn"]]
    return config
}

private func tempVault() throws -> (LocalFolderStorage, URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: "audiopencil-sync-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (LocalFolderStorage(root: root, usesTrash: false), root)
}

struct ConfigDocumentTests {
    @Test func roundTripsThroughMarkdown() throws {
        let config = sampleConfig()
        let markdown = ConfigDocument.render(config)
        #expect(markdown.contains("```yaml\n"))
        #expect(markdown.contains("instructions: |-"))
        #expect(try ConfigDocument.parse(markdown) == config)
    }

    @Test func styleConversionRoundTrips() {
        for style in Style.presets {
            #expect(ConfigStyle(style).style == style)
        }
        #expect(ConfigStyle(.polished).tone == "as-spoken")
    }

    @Test func acceptsHandWrittenYAMLWithMissingKeys() throws {
        let markdown = """
            # Notes I added
            ```yaml
            vocabulary: [Obsidian, "Dave's router"]
            styles:
              - id: haiku
                name: Haiku
                shortcut: 7
                instructions: Turn it into a haiku.
            devices:
              Work Mac:
                stop: double-tap-fn
            ```
            Trailing text.
            """
        let config = try ConfigDocument.parse(markdown)
        #expect(config.vocabulary == ["Obsidian", "Dave's router"])
        let style = try #require(config.styles.first).style
        #expect(style.name == "Haiku" && style.shortcut == 7 && style.isEnabled && style.intensity == .moderate)
        var settings = DictationSettings()
        config.devices["Work Mac"]?.apply(to: &settings)
        #expect(settings.stopGesture == .doubleTapFn)
        #expect(settings.returnStops) // missing keys keep defaults
    }

    @Test func reportsYAMLErrorsWithNoteLineNumbers() {
        let markdown = "# Settings\n\n```yaml\nvocabulary:\n  - one\n bad: [unclosed\n```\n"
        #expect {
            try ConfigDocument.parse(markdown)
        } throws: { error in
            guard case ConfigError.invalidYAML(let detail) = error else { return false }
            return detail.contains("line")
        }
        #expect(throws: ConfigError.missingYAMLBlock) { try ConfigDocument.parse("# Just a note") }
        #expect(throws: ConfigError.invalidYAML("styles.0.shortcut: expected a number")) {
            try ConfigDocument.parse("```yaml\nstyles:\n  - id: x\n    shortcut: seven\n```")
        }
    }

    @Test func quotesOnlyWhenNeeded() {
        #expect(ConfigDocument.scalar("Polished") == "Polished")
        #expect(ConfigDocument.scalar("yes") == "\"yes\"")
        #expect(ConfigDocument.scalar("a: b") == "\"a: b\"")
        #expect(ConfigDocument.scalar("say \"hi\"") == "\"say \\\"hi\\\"\"")
    }
}

struct ConfigMergerTests {
    private let device = "Mac"

    @Test func languageVocabularyMergesPerLanguage() {
        var base = SharedConfig()
        base.languageVocabulary = ["fr": ["Loïc"]]
        var local = base
        local.languageVocabulary["fr"] = ["Loïc", "Marie-Diane"] // added here
        local.languageVocabulary["es"] = ["Tío Pepe"]
        var remote = base
        remote.languageVocabulary["fr"] = [] // Loïc removed in Obsidian
        let merged = ConfigMerger.merge(base: base, local: local, remote: remote, device: "Mac")
        #expect(merged.languageVocabulary == ["fr": ["Marie-Diane"], "es": ["Tío Pepe"]])
    }

    @Test func listsMergeAdditionsAndRemovalsFromBothSides() {
        #expect(ConfigMerger.mergeList(base: ["a", "b"], local: ["a", "b", "c"], remote: ["b", "d"]) == ["b", "d", "c"])
        #expect(ConfigMerger.mergeList(base: nil, local: ["a", "x"], remote: ["a", "b"]) == ["a", "b", "x"])
    }

    @Test func stylesFollowWhoeverChangedThem() {
        let base = [ConfigStyle(.polished), ConfigStyle(.diary), ConfigStyle(.professional)]
        var localPolished = ConfigStyle(.polished); localPolished.name = "Polished (local)"
        var remoteDiary = ConfigStyle(.diary); remoteDiary.instructions = "Edited in Obsidian"
        var newLocal = ConfigStyle(.polished); newLocal.id = "mine"
        let local = [localPolished, ConfigStyle(.diary), newLocal] // professional deleted here
        let remote = [ConfigStyle(.polished), remoteDiary, ConfigStyle(.professional)]
        let merged = ConfigMerger.mergeStyles(base: base, local: local, remote: remote)
        #expect(merged.map(\.id) == ["polished", "diary", "mine"])
        #expect(merged[0].name == "Polished (local)")
        #expect(merged[1].instructions == "Edited in Obsidian")
    }

    @Test func bothChangedSameStyleVaultWins() {
        var local = ConfigStyle(.diary); local.name = "Local"
        var remote = ConfigStyle(.diary); remote.name = "Remote"
        let merged = ConfigMerger.mergeStyles(base: [ConfigStyle(.diary)], local: [local], remote: [remote])
        #expect(merged.first?.name == "Remote")
    }

    @Test func deviceSectionPrefersLocalUnlessOnlyEditedInVault() {
        var base = SharedConfig(); base.devices[device] = DeviceSection()
        var local = base
        var remote = base
        remote.devices[device]?.returnStops = false // edited in Obsidian
        remote.devices["iPhone"] = DeviceSection()
        var merged = ConfigMerger.merge(base: base, local: local, remote: remote, device: device)
        #expect(merged.devices[device]?.returnStops == false)
        #expect(merged.devices["iPhone"] != nil)

        local.devices[device]?.holdForRaw = false // changed here too
        merged = ConfigMerger.merge(base: base, local: local, remote: remote, device: device)
        #expect(merged.devices[device]?.holdForRaw == false)
    }
}

/// Lets a test change the file "from another device" just before a conditional write.
private final class RacingStorage: StorageProvider, @unchecked Sendable {
    let inner: LocalFolderStorage
    private let raced = OSAllocatedUnfairLock(initialState: false)
    let race: @Sendable () async throws -> Void

    init(inner: LocalFolderStorage, race: @escaping @Sendable () async throws -> Void) {
        self.inner = inner
        self.race = race
    }

    func list(_ path: String) async throws -> [StorageItem] { try await inner.list(path) }
    func item(at path: String) async throws -> StorageItem? { try await inner.item(at: path) }
    func read(_ path: String) async throws -> (data: Data, etag: String?) { try await inner.read(path) }
    func createFolder(_ path: String) async throws { try await inner.createFolder(path) }
    func delete(_ path: String) async throws { try await inner.delete(path) }
    func write(_ path: String, data: Data, ifMatch: String?, createOnly: Bool) async throws -> String? {
        if ifMatch != nil, !raced.withLock({ let was = $0; $0 = true; return was }) {
            try await race()
        }
        return try await inner.write(path, data: data, ifMatch: ifMatch, createOnly: createOnly)
    }
}

struct ConfigSyncTests {
    private let device = "Mac"

    private func local(vocabulary: [String] = ["Nextcloud"]) -> SharedConfig {
        var config = SharedConfig()
        config.vocabulary = vocabulary
        config.styles = Style.presets.map(ConfigStyle.init)
        config.devices[device] = DeviceSection()
        return config
    }

    @Test func firstSyncCreatesFileThenStaysQuiet() async throws {
        let (storage, root) = try tempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let sync = ConfigSync(stateURL: root.appending(path: ".state/sync.json"))

        let first = try await sync.sync(local: local(), device: device, provider: storage, vaultPath: "/", location: "test")
        #expect(first == .merged(local(), wroteFile: true))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Audio Pencil/Settings.md").path))

        let second = try await sync.sync(local: local(), device: device, provider: storage, vaultPath: "/", location: "test")
        #expect(second == .unchanged(local()))
    }

    @Test func picksUpObsidianEditsAndWritesLocalChanges() async throws {
        let (storage, root) = try tempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let sync = ConfigSync(stateURL: root.appending(path: ".state/sync.json"))
        _ = try await sync.sync(local: local(), device: device, provider: storage, vaultPath: "/", location: "test")

        // Hand edit in Obsidian: add a word.
        let path = ConfigSync.filePath(inVault: "/")
        let text = String(decoding: try await storage.read(path).data, as: UTF8.self)
        try await Task.sleep(for: .milliseconds(20))
        try await storage.write(path, data: Data(text.replacingOccurrences(of: "  - Nextcloud\n", with: "  - Nextcloud\n  - Obsidian\n").utf8), ifMatch: nil, createOnly: false)

        // Meanwhile the app added a different word.
        let outcome = try await sync.sync(local: local(vocabulary: ["Nextcloud", "WhisperKit"]), device: device, provider: storage, vaultPath: "/", location: "test")
        guard case .merged(let merged, let wrote) = outcome else { Issue.record("expected merge"); return }
        #expect(merged.vocabulary == ["Nextcloud", "Obsidian", "WhisperKit"])
        #expect(wrote)
        let onDisk = try ConfigDocument.parse(String(decoding: try await storage.read(path).data, as: UTF8.self))
        #expect(onDisk.vocabulary == merged.vocabulary)
    }

    @Test func retriesWhenAnotherDeviceWritesInBetween() async throws {
        let (storage, root) = try tempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let sync = ConfigSync(stateURL: root.appending(path: ".state/sync.json"))
        _ = try await sync.sync(local: local(), device: device, provider: storage, vaultPath: "/", location: "test")

        let path = ConfigSync.filePath(inVault: "/")
        let racing = RacingStorage(inner: storage) {
            var other = try ConfigDocument.parse(String(decoding: try await storage.read(path).data, as: UTF8.self))
            other.tags.append("from-iphone")
            try await Task.sleep(for: .milliseconds(20))
            try await storage.write(path, data: Data(ConfigDocument.render(other).utf8), ifMatch: nil, createOnly: false)
        }
        let outcome = try await sync.sync(local: local(vocabulary: ["Nextcloud", "MLX"]), device: device, provider: racing, vaultPath: "/", location: "test")
        guard case .merged(let merged, _) = outcome else { Issue.record("expected merge"); return }
        #expect(merged.tags == ["from-iphone"])
        #expect(merged.vocabulary == ["Nextcloud", "MLX"])
    }

    @Test func brokenYAMLStopsSyncWithoutOverwriting() async throws {
        let (storage, root) = try tempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let sync = ConfigSync(stateURL: root.appending(path: ".state/sync.json"))
        let path = ConfigSync.filePath(inVault: "/")
        let broken = Data("```yaml\nvocabulary: [oops\n```\n".utf8)
        try await storage.write(path, data: broken, ifMatch: nil, createOnly: false)

        await #expect(throws: ConfigError.self) {
            _ = try await sync.sync(local: local(), device: device, provider: storage, vaultPath: "/", location: "test")
        }
        #expect(try await storage.read(path).data == broken)
    }
}

/// Fails every write with a network error.
private struct OfflineStorage: StorageProvider {
    func list(_ path: String) async throws -> [StorageItem] { throw StorageError.transport("offline") }
    func item(at path: String) async throws -> StorageItem? { throw StorageError.transport("offline") }
    func read(_ path: String) async throws -> (data: Data, etag: String?) { throw StorageError.transport("offline") }
    func write(_ path: String, data: Data, ifMatch: String?, createOnly: Bool) async throws -> String? { throw StorageError.transport("offline") }
    func createFolder(_ path: String) async throws { throw StorageError.transport("offline") }
    func delete(_ path: String) async throws { throw StorageError.transport("offline") }
}

struct OutboxTests {
    @Test func uploadsInOrderAndRenamesOnClash() async throws {
        let (storage, root) = try tempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let outbox = Outbox(directory: root.appending(path: ".outbox"))
        try await outbox.enqueue(path: "/Notes/Today.md", data: Data("one".utf8))
        try await outbox.enqueue(path: "/Notes/Today.md", data: Data("two".utf8))

        let result = await outbox.drain(to: storage, vaultPath: "/Vault")
        #expect(result.uploaded == ["/Vault/Notes/Today.md", "/Vault/Notes/Today-2.md"])
        #expect(result.stoppedBecause == nil)
        #expect(await outbox.pending.isEmpty)
        #expect(String(decoding: try await storage.read("/Vault/Notes/Today-2.md").data, as: UTF8.self) == "two")
    }

    @Test func keepsItemsWhenOfflineAndBacksOff() async throws {
        let (_, root) = try tempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: ".outbox")
        let now = Date(timeIntervalSince1970: 1_000_000)
        let outbox = Outbox(directory: directory)
        try await outbox.enqueue(path: "/a.md", data: Data("a".utf8), now: now)

        let result = await outbox.drain(to: OfflineStorage(), vaultPath: "/", now: now)
        #expect(result.stoppedBecause == "offline")
        let item = try #require(await outbox.pending.first)
        #expect(item.attempts == 1)
        #expect(item.nextAttempt == now.addingTimeInterval(5))

        // Not due yet: skipped. And the queue survives a restart.
        let reopened = Outbox(directory: directory)
        #expect(await reopened.pending.count == 1)
        let early = await reopened.drain(to: OfflineStorage(), vaultPath: "/", now: now.addingTimeInterval(1))
        #expect(early == .init())
    }

    @Test func suffixRule() {
        #expect(StoragePath.withSuffix("/Notes/2026-10-19 1430 Title.md", 2) == "/Notes/2026-10-19 1430 Title-2.md")
        #expect(StoragePath.withSuffix("/audio/clip", 3) == "/audio/clip-3")
    }
}

struct StarterKitTests {
    @Test func createsBoardGuideAndSamplesOnceWithoutOverwriting() async throws {
        let (storage, root) = try tempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try await StarterKit.ensure(in: storage, vaultPath: "/Vault", includeSamples: true)
        guard case .created(let files) = first else { Issue.record("expected files"); return }
        #expect(files.count == 5)
        #expect(files.contains(StarterKit.basePath))
        #expect(files.filter { $0.hasPrefix(StarterKit.samplesFolder) }.count == 3)

        // The user edits the guide; a later run must not touch it, and samples aren't recreated.
        let guide = StoragePath.join("/Vault", StarterKit.guidePath)
        try await storage.write(guide, data: Data("mine".utf8), ifMatch: nil, createOnly: false)
        let samples = try await storage.list(StoragePath.join("/Vault", StarterKit.samplesFolder))
        for sample in samples { try await storage.delete(sample.path) }
        let second = try await StarterKit.ensure(in: storage, vaultPath: "/Vault", includeSamples: false)
        #expect(second == .alreadyThere)
        #expect(try await storage.read(guide).data == Data("mine".utf8))
        #expect(try await storage.list(StoragePath.join("/Vault", StarterKit.samplesFolder)).isEmpty)

        // A deleted board comes back (PRD: created when missing).
        try await storage.delete(StoragePath.join("/Vault", StarterKit.basePath))
        #expect(try await StarterKit.ensure(in: storage, vaultPath: "/Vault", includeSamples: false) == .created(files: [StarterKit.basePath]))
    }

    @Test func boardIsValidYAMLWithTheThreeViews() throws {
        let parsed = try #require(try Yams.load(yaml: StarterKit.base) as? [String: Any])
        let views = try #require(parsed["views"] as? [[String: Any]])
        #expect(views.compactMap { $0["name"] as? String } == ["Professional review", "Diary", "All recordings", "Retention"])
        #expect(views.first?["type"] as? String == "kanban")
        #expect((views.first?["groupOrder"] as? [String]) == ["needs-review", "reviewed", "actioned"])
    }

    @Test func samplesRenderAsAudioPencilNotes() {
        for note in StarterKit.samples() {
            let markdown = NoteRenderer.markdown(for: note)
            #expect(markdown.contains("type: audio-pencil\n"))
            #expect(markdown.contains("  - sample\n"))
        }
        #expect(StarterKit.samples().map(\.status) == [.reviewed, .reviewed, .needsReview])
    }
}

struct NoteFrontmatterTests {
    private let note = "---\ntype: audio-pencil\nstatus: reviewed\ntags:\n  - work\naudio: \"[[Audio Pencil/Recordings/a.m4a]]\"\n---\n\n![[Audio Pencil/Recordings/a.m4a]]\n\nBody text.\n"

    @Test func readsValues() {
        #expect(NoteFrontmatter.string("type", in: note) == "audio-pencil")
        #expect(NoteFrontmatter.linkTarget(NoteFrontmatter.string("audio", in: note)!) == "/Audio Pencil/Recordings/a.m4a")
        #expect(NoteFrontmatter.string("missing", in: note) == nil)
        #expect(NoteFrontmatter.string("type", in: "No frontmatter") == nil)
    }

    @Test func editsOnlyTheKey() {
        var edited = NoteFrontmatter.setting("status", to: "actioned", in: note)
        #expect(edited.contains("status: actioned\ntags:\n  - work"))
        edited = NoteFrontmatter.setting("tags", to: nil, in: edited)
        #expect(!edited.contains("work"))
        edited = NoteFrontmatter.setting("retention", to: "archive", in: edited)
        #expect(edited.contains("retention: archive\n---"))
        edited = NoteFrontmatter.removingEmbeds(of: "/Audio Pencil/Recordings/a.m4a", in: edited)
        #expect(!edited.contains("![["))
        #expect(edited.hasSuffix("\nBody text.\n"))
    }
}

struct RetentionKeeperTests {
    private let now = ISO8601DateFormatter().date(from: "2027-11-01T12:00:00Z")!

    private func write(_ storage: LocalFolderStorage, _ name: String, retention: String?, recorded: String, audio: Bool) async throws {
        let audioPath = "/Audio Pencil/Recordings/\(name).m4a"
        if audio { try await storage.write("/V" + audioPath, data: Data("aac".utf8), ifMatch: nil, createOnly: false) }
        var lines = ["---", "type: audio-pencil", "recorded: \(recorded)"]
        if let retention { lines.append("retention: \(retention)") }
        if audio { lines.append("audio: \"[[\(audioPath.dropFirst())]]\"") }
        lines += ["---", "", audio ? "![[\(audioPath.dropFirst())]]" : "", "Text of \(name)."]
        try await storage.write("/V/Notes/\(name).md", data: Data(lines.joined(separator: "\n").utf8), ifMatch: nil, createOnly: false)
    }

    @Test func appliesTheThreeColumns() async throws {
        let (storage, root) = try tempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try await write(storage, "old-regular", retention: "regular", recorded: "2026-10-01T10:00:00Z", audio: true)
        try await write(storage, "old-archive", retention: "archive", recorded: "2026-10-01T10:00:00Z", audio: true)
        try await write(storage, "to-delete", retention: "delete", recorded: "2027-10-30T10:00:00Z", audio: true)
        try await write(storage, "expiring", retention: "regular", recorded: "2026-11-15T10:00:00Z", audio: true)
        try await write(storage, "legacy", retention: nil, recorded: "2027-10-01T10:00:00Z", audio: false)
        try await storage.write("/V/Notes/not-ours.md", data: Data("---\ntitle: mine\nretention: delete\n---\nKeep me".utf8), ifMatch: nil, createOnly: false)

        let keeper = RetentionKeeper(stateURL: root.appending(path: ".state/retention.json"))
        let report = await keeper.run(provider: storage, vaultPath: "/V", folders: ["/Notes"], expireRegularAudio: true, now: now)

        #expect(report.errors.isEmpty)
        #expect(report.deletedNotes == ["/V/Notes/to-delete.md"])
        #expect(try await storage.item(at: "/V/Audio Pencil/Recordings/to-delete.m4a") == nil)
        #expect(report.expiredAudio == ["/Audio Pencil/Recordings/old-regular.m4a"])
        #expect(try await storage.item(at: "/V/Audio Pencil/Recordings/old-archive.m4a") != nil)
        #expect(report.backfilled == ["/V/Notes/legacy.md"])
        #expect(report.expiringSoon.map(\.title) == ["expiring"])
        #expect(try await storage.item(at: "/V/Notes/not-ours.md") != nil) // only audio-pencil notes are touched

        let regular = String(decoding: try await storage.read("/V/Notes/old-regular.md").data, as: UTF8.self)
        #expect(!regular.contains("audio:") && !regular.contains("![[") && regular.contains("audio_expired: 2027-11-01"))
        #expect(regular.contains("Text of old-regular."))
        #expect(String(decoding: try await storage.read("/V/Notes/legacy.md").data, as: UTF8.self).contains("retention: regular"))

        // A second run with nothing changed does nothing.
        let again = await keeper.run(provider: storage, vaultPath: "/V", folders: ["/Notes"], expireRegularAudio: true, now: now)
        #expect(again.deletedNotes.isEmpty && again.expiredAudio.isEmpty && again.backfilled.isEmpty)
    }

    @Test func yearRuleCanBeOff() async throws {
        let (storage, root) = try tempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try await write(storage, "old-regular", retention: "regular", recorded: "2026-10-01T10:00:00Z", audio: true)
        let keeper = RetentionKeeper(stateURL: root.appending(path: ".state/retention.json"))
        let report = await keeper.run(provider: storage, vaultPath: "/V", folders: ["/Notes"], expireRegularAudio: false, now: now)
        #expect(report.expiredAudio.isEmpty)
        #expect(try await storage.item(at: "/V/Audio Pencil/Recordings/old-regular.m4a") != nil)
    }
}

struct BoardUpgradeTests {
    @Test func upgradesAnUnchangedBoardButNotACustomisedOne() async throws {
        let (storage, root) = try tempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let board = StoragePath.join("/V", StarterKit.basePath)
        try await storage.write(board, data: Data(StarterKit.previousBases[0].utf8), ifMatch: nil, createOnly: false)
        let upgraded = try await StarterKit.ensure(in: storage, vaultPath: "/V", includeSamples: false)
        #expect(upgraded == .created(files: [StarterKit.basePath, StarterKit.guidePath]))
        #expect(String(decoding: try await storage.read(board).data, as: UTF8.self).contains("name: Retention"))

        try await storage.write(board, data: Data("views: []  # mine".utf8), ifMatch: nil, createOnly: false)
        #expect(try await StarterKit.ensure(in: storage, vaultPath: "/V", includeSamples: false) == .boardCustomised)
    }
}

struct BoardMaintenanceTests {
    private let board = StoragePath.join("/V", StarterKit.basePath)

    @Test func addsMissingViewsAndKeepsCustomisations() async throws {
        let (storage, root) = try tempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        // As Obsidian might leave it: reformatted, with a user view and view state, Retention missing.
        let customised = """
            filters:
              and:
                - type == "audio-pencil"
            formulas:
              age: 'now() - recorded'
            views:
              - type: kanban
                name: Professional review
                groupBy:
                  property: note.status
                  direction: ASC
              - type: table
                name: My own view
                order: [file.name]
              - type: table
                name: Diary
              - type: table
                name: All recordings
            """
        try await storage.write(board, data: Data(customised.utf8), ifMatch: nil, createOnly: false)
        #expect(try await StarterKit.ensureBoard(in: storage, vaultPath: "/V") == .addedViews(["Retention"]))
        let text = String(decoding: try await storage.read(board).data, as: UTF8.self)
        let views = try #require((try Yams.load(yaml: text) as? [String: Any])?["views"] as? [[String: Any]])
        #expect(views.compactMap { $0["name"] as? String } == ["Professional review", "My own view", "Diary", "All recordings", "Retention"])
        #expect(text.contains("now() - recorded"))
        #expect(try await StarterKit.ensureBoard(in: storage, vaultPath: "/V") == .ok)
    }

    @Test func leavesABrokenBoardAloneUntilAskedThenSalvages() async throws {
        let (storage, root) = try tempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let broken = """
            filters:
              and:
                - type == "audio-pencil"
            views:
              - type: table
                name: My own view
                order: [file.name]
              - type: kanban
                name: Broken one
                groupBy: [unclosed
            """
        try await storage.write(board, data: Data(broken.utf8), ifMatch: nil, createOnly: false)
        guard case .unparseable = try await StarterKit.ensureBoard(in: storage, vaultPath: "/V") else { Issue.record("expected unparseable"); return }
        #expect(try await storage.read(board).data == Data(broken.utf8)) // untouched

        let repair = try await StarterKit.repairBoard(in: storage, vaultPath: "/V")
        #expect(repair.keptViews == ["My own view"])
        #expect(repair.droppedSections == 1)
        let text = String(decoding: try await storage.read(board).data, as: UTF8.self)
        let names = ((try Yams.load(yaml: text) as? [String: Any])?["views"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        #expect(names == ["My own view"] + StarterKit.requiredViewNames)
        #expect(try await storage.read(repair.backupPath).data.count > broken.count)
    }
}

struct SettingsRepairTests {
    @Test func keepsValidEditsAndRestoresBrokenParts() async throws {
        let (storage, root) = try tempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let sync = ConfigSync(stateURL: root.appending(path: ".state/sync.json"))
        var local = SharedConfig()
        local.vocabulary = ["Nextcloud"]
        local.tags = ["work"]
        local.styles = [ConfigStyle(.polished), ConfigStyle(.diary)]
        _ = try await sync.sync(local: local, device: "Mac", provider: storage, vaultPath: "/V", location: "t")

        // In Obsidian: a valid new tag, a renamed style, and a typo that breaks vocabulary and the diary style.
        let broken = """
            # Audio Pencil settings
            ```yaml
            version: 1
            vocabulary: [Nextcloud, "unclosed
            tags:
              - work
              - home
            styles:
              - id: polished
                name: Polished (mine)
                shortcut: 1
                instructions: Rewrite it.
              - id: diary
                name: Diary
                shortcut: [oops
            ```
            """
        let path = ConfigSync.filePath(inVault: "/V")
        try await storage.write(path, data: Data(broken.utf8), ifMatch: nil, createOnly: false)
        await #expect(throws: ConfigError.self) { _ = try await sync.sync(local: local, device: "Mac", provider: storage, vaultPath: "/V", location: "t") }

        let repair = try await sync.repair(fallback: local, device: "Mac", provider: storage, vaultPath: "/V", location: "t")
        #expect(repair.config.tags == ["work", "home"])                 // valid edit kept
        #expect(repair.config.styles.first?.name == "Polished (mine)")  // valid style edit kept
        #expect(repair.config.styles.map(\.id) == ["polished", "diary"]) // broken style restored
        #expect(repair.config.vocabulary == ["Nextcloud"])               // broken section restored
        #expect(repair.restored.contains("vocabulary"))
        #expect(try await storage.read(repair.backupPath).data == Data(broken.utf8))
        // Syncing works again.
        let after = try await sync.sync(local: repair.config, device: "Mac", provider: storage, vaultPath: "/V", location: "t")
        #expect(after == .unchanged(repair.config))
    }
}
