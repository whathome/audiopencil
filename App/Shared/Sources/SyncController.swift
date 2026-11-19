import APCore
import APModels
import APStorage
import APSync
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Network

/// Keeps the vault's settings file in step with the app and uploads the offline queue.
/// Syncs shortly after local changes, every minute, when the app becomes active, and when the
/// network comes back.
@Observable
final class SyncController {
    enum Status: Equatable {
        case notConfigured
        case idle
        case syncing
        case offline
        /// The settings file has a mistake; syncing waits until it's fixed in Obsidian.
        case paused(String)
        case failed(String)
    }

    private(set) var status: Status = .notConfigured
    private(set) var lastSynced: Date?
    private(set) var queuedUploads = 0
    /// Regular notes whose audio goes within 30 days.
    private(set) var expiringSoon: [RetentionKeeper.Expiring] = []
    /// The board file doesn't parse (left alone until repaired).
    private(set) var boardProblem: String?
    /// Result of the last repair, for a confirmation message.
    private(set) var repairSummary: String?
    /// The last repair was of the board (shown on the Notes page) rather than the settings file.
    private(set) var repairedBoard = false
    /// Last retention pass, for the Notes page.
    private(set) var lastRetention: RetentionKeeper.Report?
    /// First-run files were just created in this vault: show the board walkthrough once.
    var showWalkthrough = false
    /// Whether Obsidian's Daily notes is on in this vault (checked every sync), and how it's set up.
    private(set) var dailyNotes: DailyNotesAvailability = .unknown
    @ObservationIgnored private(set) var dailyNotesSetup: DailyNotesSetup?
    @ObservationIgnored let appends: AppendQueue
    #if os(macOS)
    let deviceName = Host.current().localizedName ?? "Mac"
    #else
    /// iOS only shares the model name ("iPhone") without a special entitlement.
    let deviceName = UIDevice.current.name
    #endif

    /// Builds the local side of the merge from the last agreed version.
    @ObservationIgnored var localConfig: ((SharedConfig?) -> SharedConfig)?
    /// Applies a merged config to the app.
    @ObservationIgnored var apply: ((SharedConfig) -> Void)?
    /// Folders notes land in (scanned by the retention pass).
    @ObservationIgnored var retentionFolders: (() -> [String])?
    @ObservationIgnored var expireRegularAudio: (() -> Bool)?
    /// Vault paths of the notes the app lists as filed; `filedNotesGone` gets the ones no longer there
    /// (deleted or moved in Obsidian, or on the server).
    @ObservationIgnored var filedNotePaths: (() -> [String])?
    @ObservationIgnored var filedNotesGone: (([String]) -> Void)?

    @ObservationIgnored private let vault: VaultController
    @ObservationIgnored private let configSync: ConfigSync
    @ObservationIgnored let outbox: Outbox
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var isOnline = true
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    /// Vaults whose board and guide were checked this launch.
    @ObservationIgnored private var starterChecked: Set<String> = []
    @ObservationIgnored private let retention: RetentionKeeper
    @ObservationIgnored private var lastRetentionRun = Date.distantPast

    init(vault: VaultController) {
        self.vault = vault
        let folder = ModelLocations.root.deletingLastPathComponent().appending(path: "Sync", directoryHint: .isDirectory)
        configSync = ConfigSync(stateURL: folder.appending(path: "config-state.json"))
        outbox = Outbox(directory: folder.appending(path: "Outbox", directoryHint: .isDirectory))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        appends = AppendQueue(url: folder.appending(path: "appends.json"))
        retention = RetentionKeeper(stateURL: folder.appending(path: "retention-state.json"))
    }

    var settingsFilePath: String? {
        guard let location = vault.vaultLocation else { return nil }
        return ConfigSync.filePath(inVault: location.path)
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let cameBack = online && !self.isOnline
                self.isOnline = online
                if cameBack {
                    self.syncSoon(after: .seconds(1))
                } else if !online, self.status != .notConfigured {
                    self.status = .offline
                }
            }
        }
        monitor.start(queue: .global(qos: .utility))
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.syncSoon(after: .zero)
            }
        }
        #if os(macOS)
        let becameActive = NSApplication.didBecomeActiveNotification
        #else
        let becameActive = UIApplication.didBecomeActiveNotification
        #endif
        activationObserver = NotificationCenter.default.addObserver(forName: becameActive, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lastRetentionRun = .distantPast // "the next time the app is aware": check on activation too
                self?.syncSoon(after: .milliseconds(500))
            }
        }
        syncSoon(after: .seconds(1))
    }

    /// Debounced: bursts of edits become one sync.
    func syncSoon(after delay: Duration = .seconds(2)) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// First launch: nothing is written to storage until setup finishes, so trying a few places leaves
    /// no files behind in the ones not chosen.
    var isHeld = false

    func syncNow() async {
        guard !isHeld else { return }
        if let running { await running.value; return } // one at a time
        let task = Task { await performSync() }
        running = task
        await task.value
        running = nil
    }

    /// Adds a line to a vault file at the next sync (now, if online).
    func append(_ entry: String, to target: PendingAppend.Target, heading: String?) {
        Task {
            await appends.add(PendingAppend(target: target, entry: entry, heading: heading))
            syncSoon(after: .zero)
        }
    }

    private func performSync() async {
        queuedUploads = await outbox.pending.count
        guard vault.settings.isConfigured, let location = vault.vaultLocation, let localConfig, let apply else {
            status = .notConfigured
            dailyNotes = .unknown
            return
        }
        guard isOnline || vault.settings.kind == .localFolder else {
            status = .offline
            return
        }
        status = .syncing
        do {
            let base = await configSync.base
            let outcome = try await configSync.sync(
                local: localConfig(base),
                device: deviceName,
                provider: location.provider,
                vaultPath: location.path,
                location: locationKey
            )
            if case .merged(let config, let wrote) = outcome {
                apply(config)
                Log.models.notice("Settings synced\(wrote ? " (file updated)" : "", privacy: .public)")
            }
            if let layout = vault.layout {
                await ensureStarterKit(provider: location.provider, vaultPath: location.path, layout: layout)
                if layout == .plain, (try? await location.provider.item(at: StoragePath.join(location.path, ".obsidian"))) != nil {
                    vault.noticeObsidianFolder()
                }
            }
            let drained = await outbox.drain(to: location.provider, vaultPath: location.path)
            // Daily notes: only an Obsidian vault has them, and only with the core plugin on.
            dailyNotesSetup = vault.layout == .obsidian ? await DailyNotesSetup.load(from: location.provider, vaultPath: location.path) : nil
            dailyNotes = dailyNotesSetup == nil ? .off : .on
            await appends.flush(to: location.provider, vaultPath: location.path, daily: dailyNotesSetup)
            await checkFiledNotes(provider: location.provider, vaultPath: location.path)
            if Date().timeIntervalSince(lastRetentionRun) > 300, let folders = retentionFolders?() {
                lastRetentionRun = Date()
                if vault.layout == .obsidian { await checkBoard(provider: location.provider, vaultPath: location.path) }
                let report = await retention.run(
                    provider: location.provider, vaultPath: location.path, folders: folders,
                    expireRegularAudio: expireRegularAudio?() ?? true
                )
                lastRetention = report
                expiringSoon = report.expiringSoon
                if !report.deletedNotes.isEmpty || !report.expiredAudio.isEmpty || !report.backfilled.isEmpty {
                    Log.models.notice("Retention: deleted \(report.deletedNotes.count) notes, removed \(report.expiredAudio.count) expired recordings, marked \(report.backfilled.count) older notes regular")
                }
            }
            queuedUploads = await outbox.pending.count
            if let reason = drained.stoppedBecause {
                status = .failed(String(localized: "Uploads waiting: \(reason)"))
            } else {
                status = .idle
                lastSynced = Date()
            }
        } catch let error as ConfigError {
            status = .paused(error.localizedDescription)
        } catch StorageError.transport(let detail) {
            status = isOnline ? .failed(detail) : .offline
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Keeps the board's required views in place (re-adding any that went missing).
    private func checkBoard(provider: any StorageProvider, vaultPath: String) async {
        do {
            switch try await StarterKit.ensureBoard(in: provider, vaultPath: vaultPath) {
            case .ok, .created:
                boardProblem = nil
            case .addedViews(let names):
                boardProblem = nil
                Log.models.notice("Board: added missing views \(names.joined(separator: ", "), privacy: .public)")
            case .unparseable(let detail):
                boardProblem = detail
            }
        } catch {
            Log.models.error("Board check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Repairs a settings file that won't parse, keeping every part that still does.
    func repairSettings() async {
        guard let location = vault.vaultLocation, let localConfig, let apply else { return }
        do {
            let base = await configSync.base
            let repair = try await configSync.repair(fallback: localConfig(base), device: deviceName, provider: location.provider, vaultPath: location.path, location: locationKey)
            apply(repair.config)
            let restored = repair.restored.isEmpty ? String(localized: "nothing") : repair.restored.joined(separator: "; ")
            repairSummary = String(localized: "Settings repaired. Kept: \(repair.kept.joined(separator: ", ")). Restored from the last good version: \(restored). The broken copy is in \(String(repair.backupPath.dropFirst())).")
            repairedBoard = false
            status = .idle
            lastSynced = Date()
        } catch {
            status = .failed(String(localized: "Repair failed: \(error.localizedDescription)"))
        }
    }

    /// Repairs a board that won't parse, keeping every view that still does.
    func repairBoard() async {
        guard let location = vault.vaultLocation else { return }
        do {
            let repair = try await StarterKit.repairBoard(in: location.provider, vaultPath: location.path)
            boardProblem = nil
            let kept = repair.keptViews.isEmpty ? String(localized: "none") : repair.keptViews.joined(separator: ", ")
            repairSummary = String(localized: "Board repaired. Kept your views: \(kept). The broken copy is in \(String(repair.backupPath.dropFirst())).")
            repairedBoard = true
        } catch {
            boardProblem = String(localized: "Repair failed: \(error.localizedDescription)")
        }
    }

    func clearRepairSummary() { repairSummary = nil }

    /// Keep forever or Delete from the app (the board's Retention view does the same in Obsidian): sets the
    /// note's `retention`. A deleted note goes, with its audio, at the retention check run straight after.
    /// Lists each folder the filed notes are in (one request per folder) and reports the notes missing
    /// from it. Notes still waiting to upload aren't checked, and a folder that can't be listed is skipped
    /// unless it's gone altogether.
    private func checkFiledNotes(provider: any StorageProvider, vaultPath: String) async {
        guard let paths = filedNotePaths?(), !paths.isEmpty, let filedNotesGone else { return }
        let uploading = Set(await outbox.pending.map(\.path))
        let byFolder = Dictionary(grouping: paths.filter { !uploading.contains($0) }, by: StoragePath.parent(of:))
        var gone: [String] = []
        for (folder, notes) in byFolder {
            do {
                let names = Set(try await provider.list(StoragePath.join(vaultPath, folder)).map(\.name))
                gone += notes.filter { !names.contains($0.split(separator: "/").last.map(String.init) ?? "") }
            } catch StorageError.notFound {
                gone += notes
            } catch {
                continue
            }
        }
        if !gone.isEmpty {
            Log.models.notice("\(gone.count) filed notes are no longer in the vault")
            filedNotesGone(gone)
        }
    }

    func setRetention(_ value: Note.Retention, notePath: String) async -> Bool {
        guard let location = vault.vaultLocation else { return false }
        let path = StoragePath.join(location.path, notePath)
        do {
            let (data, etag) = try await location.provider.read(path)
            let edited = NoteFrontmatter.setting("retention", to: value.rawValue, in: String(decoding: data, as: UTF8.self))
            try await location.provider.write(path, data: Data(edited.utf8), ifMatch: etag, createOnly: false)
            if value == .delete {
                lastRetentionRun = .distantPast
                syncSoon(after: .zero)
            }
            return true
        } catch {
            status = .failed(String(localized: "Couldn't update \(notePath.split(separator: "/").last.map(String.init) ?? notePath): \(error.localizedDescription)"))
            return false
        }
    }

    /// The plain folder's layout changed (adopted as a vault): set it up again for the new layout.
    func layoutChanged() {
        starterChecked.removeAll()
        syncSoon(after: .zero)
    }

    /// "Keep forever": moves a note to the Retention board's archive column.
    func archive(_ item: RetentionKeeper.Expiring) async {
        guard let location = vault.vaultLocation else { return }
        do {
            let (data, etag) = try await location.provider.read(item.notePath)
            let edited = NoteFrontmatter.setting("retention", to: "archive", in: String(decoding: data, as: UTF8.self))
            try await location.provider.write(item.notePath, data: Data(edited.utf8), ifMatch: etag, createOnly: false)
            expiringSoon.removeAll { $0.id == item.id }
        } catch {
            status = .failed(String(localized: "Couldn't archive \(item.title): \(error.localizedDescription)"))
        }
    }

    /// PRD first run: the board and guide whenever they're missing; samples once per vault.
    private func ensureStarterKit(provider: any StorageProvider, vaultPath: String, layout: NoteLayout) async {
        let key = locationKey + "|" + layout.rawValue
        guard !starterChecked.contains(key) else { return }
        let samplesKey = "starterSamples:" + key
        let firstTime = !UserDefaults.standard.bool(forKey: samplesKey)
        do {
            let outcome = try await StarterKit.ensure(in: provider, vaultPath: vaultPath, includeSamples: firstTime && layout == .obsidian, layout: layout)
            starterChecked.insert(key)
            UserDefaults.standard.set(true, forKey: samplesKey)
            if case .created(let files) = outcome {
                Log.models.notice("Created in the vault: \(files.joined(separator: ", "), privacy: .public)")
                if firstTime, layout == .obsidian { showWalkthrough = true }
            }
        } catch {
            Log.models.error("Couldn't create the board and guide: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var locationKey: String {
        switch vault.settings.kind {
        case .nextcloud: "nextcloud:\(vault.settings.account?.server.absoluteString ?? "")|\(vault.settings.account?.loginName ?? "")|\(vault.settings.remoteVaultPath ?? "")"
        case .localFolder: "local:\(vault.settings.localPath ?? "")"
        case .webdav: "webdav:\(vault.settings.webdav?.server.absoluteString ?? "")|\(vault.settings.webdav?.loginName ?? "")|\(vault.settings.webdavPath ?? "")"
        }
    }
}
