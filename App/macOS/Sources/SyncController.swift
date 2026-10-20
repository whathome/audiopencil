import APCore
import APModels
import APStorage
import APSync
import AppKit
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
    /// Last retention pass, for the Notes page.
    private(set) var lastRetention: RetentionKeeper.Report?
    /// First-run files were just created in this vault: show the board walkthrough once.
    var showWalkthrough = false
    let deviceName = Host.current().localizedName ?? "Mac"

    /// Builds the local side of the merge from the last agreed version.
    @ObservationIgnored var localConfig: ((SharedConfig?) -> SharedConfig)?
    /// Applies a merged config to the app.
    @ObservationIgnored var apply: ((SharedConfig) -> Void)?
    /// Folders notes land in (scanned by the retention pass).
    @ObservationIgnored var retentionFolders: (() -> [String])?
    @ObservationIgnored var expireRegularAudio: (() -> Bool)?

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
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
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

    func syncNow() async {
        if let running { await running.value; return } // one at a time
        let task = Task { await performSync() }
        running = task
        await task.value
        running = nil
    }

    private func performSync() async {
        queuedUploads = await outbox.pending.count
        guard vault.settings.isConfigured, let location = vault.vaultLocation, let localConfig, let apply else {
            status = .notConfigured
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
            await ensureStarterKit(provider: location.provider, vaultPath: location.path)
            let drained = await outbox.drain(to: location.provider, vaultPath: location.path)
            if Date().timeIntervalSince(lastRetentionRun) > 300, let folders = retentionFolders?() {
                lastRetentionRun = Date()
                await checkBoard(provider: location.provider, vaultPath: location.path)
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
                status = .failed("Uploads waiting: \(reason)")
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
            repairSummary = "Settings repaired. Kept: \(repair.kept.joined(separator: ", ")). Restored from the last good version: \(repair.restored.isEmpty ? "nothing" : repair.restored.joined(separator: "; ")). The broken copy is in \(repair.backupPath.dropFirst())."
            status = .idle
            lastSynced = Date()
        } catch {
            status = .failed("Repair failed: \(error.localizedDescription)")
        }
    }

    /// Repairs a board that won't parse, keeping every view that still does.
    func repairBoard() async {
        guard let location = vault.vaultLocation else { return }
        do {
            let repair = try await StarterKit.repairBoard(in: location.provider, vaultPath: location.path)
            boardProblem = nil
            repairSummary = "Board repaired. Kept your views: \(repair.keptViews.isEmpty ? "none" : repair.keptViews.joined(separator: ", ")). The broken copy is in \(repair.backupPath.dropFirst())."
        } catch {
            boardProblem = "Repair failed: \(error.localizedDescription)"
        }
    }

    func clearRepairSummary() { repairSummary = nil }

    /// "Keep forever": moves a note to the Retention board's archive column.
    func archive(_ item: RetentionKeeper.Expiring) async {
        guard let location = vault.vaultLocation else { return }
        do {
            let (data, etag) = try await location.provider.read(item.notePath)
            let edited = NoteFrontmatter.setting("retention", to: "archive", in: String(decoding: data, as: UTF8.self))
            try await location.provider.write(item.notePath, data: Data(edited.utf8), ifMatch: etag, createOnly: false)
            expiringSoon.removeAll { $0.id == item.id }
        } catch {
            status = .failed("Couldn't archive \(item.title): \(error.localizedDescription)")
        }
    }

    /// PRD first run: the board and guide whenever they're missing; samples once per vault.
    private func ensureStarterKit(provider: any StorageProvider, vaultPath: String) async {
        let key = locationKey
        guard !starterChecked.contains(key) else { return }
        let samplesKey = "starterSamples:" + key
        let firstTime = !UserDefaults.standard.bool(forKey: samplesKey)
        do {
            let outcome = try await StarterKit.ensure(in: provider, vaultPath: vaultPath, includeSamples: firstTime)
            starterChecked.insert(key)
            UserDefaults.standard.set(true, forKey: samplesKey)
            if case .created(let files) = outcome {
                Log.models.notice("Created in the vault: \(files.joined(separator: ", "), privacy: .public)")
                if firstTime { showWalkthrough = true }
            }
        } catch {
            Log.models.error("Couldn't create the board and guide: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var locationKey: String {
        switch vault.settings.kind {
        case .nextcloud: "nextcloud:\(vault.settings.account?.server.absoluteString ?? "")|\(vault.settings.account?.loginName ?? "")|\(vault.settings.remoteVaultPath ?? "")"
        case .localFolder: "local:\(vault.settings.localPath ?? "")"
        }
    }
}
