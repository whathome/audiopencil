import APCore
import APStorage
@testable import APSync
import Foundation
import Testing
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
    config.devices = ["Wes’s MacBook Air": device, "iPhone": DeviceSection()]
    return config
}

private func tempVault() throws -> (LocalFolderStorage, URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: "audiopencil-sync-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (LocalFolderStorage(root: root), root)
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
