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
    let deviceName = Host.current().localizedName ?? "Mac"

    /// Builds the local side of the merge from the last agreed version.
    @ObservationIgnored var localConfig: ((SharedConfig?) -> SharedConfig)?
    /// Applies a merged config to the app.
    @ObservationIgnored var apply: ((SharedConfig) -> Void)?

    @ObservationIgnored private let vault: VaultController
    @ObservationIgnored private let configSync: ConfigSync
    @ObservationIgnored let outbox: Outbox
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var isOnline = true
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    init(vault: VaultController) {
        self.vault = vault
        let folder = ModelLocations.root.deletingLastPathComponent().appending(path: "Sync", directoryHint: .isDirectory)
        configSync = ConfigSync(stateURL: folder.appending(path: "config-state.json"))
        outbox = Outbox(directory: folder.appending(path: "Outbox", directoryHint: .isDirectory))
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
            MainActor.assumeIsolated { self?.syncSoon(after: .milliseconds(500)) }
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
            let drained = await outbox.drain(to: location.provider, vaultPath: location.path)
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

    private var locationKey: String {
        switch vault.settings.kind {
        case .nextcloud: "nextcloud:\(vault.settings.account?.server.absoluteString ?? "")|\(vault.settings.account?.loginName ?? "")|\(vault.settings.remoteVaultPath ?? "")"
        case .localFolder: "local:\(vault.settings.localPath ?? "")"
        }
    }
}
