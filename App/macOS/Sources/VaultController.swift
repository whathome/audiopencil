import APCore
import APStorage
import AppKit

/// Connects to the vault: Nextcloud sign-in (browser or app password) or a local folder such as
/// an Obsidian vault in iCloud Drive, plus choosing and checking the vault folder.
@Observable
final class VaultController {
    enum Connection: Equatable {
        case signedOut
        case checking
        case waitingForBrowser(URL)
        case signedIn
        case failed(String)
    }

    enum LocationCheck: Equatable {
        case none
        case checking
        case ok(isObsidianVault: Bool)
        case failed(String)
    }

    private static let settingsKey = "vaultSettings"

    var settings: VaultSettings {
        didSet { save() }
    }

    var serverText = ""
    private(set) var serverDescription: String?
    private(set) var connection: Connection = .signedOut
    private(set) var locationCheck: LocationCheck = .none

    // Nextcloud folder browser
    var isBrowsing = false
    private(set) var browserPath = "/"
    private(set) var browserFolders: [StorageItem] = []
    private(set) var browserHasObsidian = false
    private(set) var browserLoading = false
    private(set) var browserError: String?

    @ObservationIgnored private var signInTask: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(VaultSettings.self, from: data) {
            settings = saved
        } else {
            settings = VaultSettings()
        }
        if let account = settings.account {
            serverText = account.server.absoluteString
            connection = Keychain.password(for: account) == nil ? .signedOut : .signedIn
        }
        if settings.isConfigured { verifyLocation() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    // MARK: Nextcloud sign-in

    /// Login Flow v2: Nextcloud opens in the browser; approving there hands back an app password.
    func signInWithBrowser() {
        guard let server = NextcloudServer.normalise(serverText) else {
            connection = .failed("Enter your Nextcloud address, like cloud.example.com.")
            return
        }
        signInTask?.cancel()
        connection = .checking
        signInTask = Task {
            do {
                let status = try await NextcloudServer.status(of: server)
                serverDescription = [status.productname, status.versionstring].compactMap { $0 }.joined(separator: " ")
                let start = try await NextcloudServer.startLogin(server: server)
                connection = .waitingForBrowser(start.loginURL)
                NSWorkspace.shared.open(start.loginURL)
                let credentials = try await NextcloudServer.waitForLogin(start)
                try finishSignIn(credentials)
            } catch is CancellationError {
                connection = .signedOut
            } catch {
                connection = .failed(error.localizedDescription)
            }
        }
    }

    /// Manual alternative: an app password created under Settings › Security › Devices & sessions.
    func signIn(user: String, appPassword: String) {
        guard let server = NextcloudServer.normalise(serverText) else {
            connection = .failed("Enter your Nextcloud address, like cloud.example.com.")
            return
        }
        let credentials = NextcloudServer.Credentials(
            account: NextcloudAccount(server: server, loginName: user.trimmingCharacters(in: .whitespaces)),
            appPassword: appPassword.trimmingCharacters(in: .whitespaces)
        )
        signInTask?.cancel()
        connection = .checking
        signInTask = Task {
            do {
                let status = try await NextcloudServer.status(of: server)
                serverDescription = [status.productname, status.versionstring].compactMap { $0 }.joined(separator: " ")
                try await NextcloudServer.verify(credentials)
                try finishSignIn(credentials)
            } catch {
                connection = .failed(error.localizedDescription)
            }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        connection = .signedOut
    }

    private func finishSignIn(_ credentials: NextcloudServer.Credentials) throws {
        try Keychain.savePassword(credentials.appPassword, for: credentials.account)
        if settings.account != credentials.account { settings.remoteVaultPath = nil }
        settings.account = credentials.account
        serverText = credentials.account.server.absoluteString
        connection = .signedIn
        locationCheck = .none
        if settings.remoteVaultPath != nil { verifyLocation() }
        Log.models.notice("Signed in to Nextcloud as \(credentials.account.loginName, privacy: .public)")
    }

    /// Revokes the app password on the server and forgets it here.
    func signOut() {
        guard let account = settings.account else { return }
        if let password = Keychain.password(for: account) {
            let credentials = NextcloudServer.Credentials(account: account, appPassword: password)
            Task { await NextcloudServer.revoke(credentials) }
        }
        Keychain.deletePassword(for: account)
        settings.account = nil
        settings.remoteVaultPath = nil
        connection = .signedOut
        locationCheck = .none
        serverDescription = nil
    }

    // MARK: Location

    private var nextcloudStorage: WebDAVStorage? {
        guard let account = settings.account, let password = Keychain.password(for: account) else { return nil }
        return WebDAVStorage(account: account, appPassword: password)
    }

    /// Provider plus the vault's path within it.
    var vaultLocation: (provider: any StorageProvider, path: String)? {
        switch settings.kind {
        case .nextcloud:
            guard let storage = nextcloudStorage, let path = settings.remoteVaultPath else { return nil }
            return (storage, path)
        case .localFolder:
            guard let url = resolvedLocalFolder else { return nil }
            return (LocalFolderStorage(root: url), "/")
        }
    }

    private var resolvedLocalFolder: URL? {
        guard let bookmark = settings.localBookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData() {
            settings.localBookmark = fresh
            settings.localPath = url.path
        }
        return url
    }

    func openBrowser() {
        isBrowsing = true
        browse(settings.remoteVaultPath.map(StoragePath.parent) ?? "/")
    }

    func browse(_ path: String) {
        guard let storage = nextcloudStorage else { return }
        browserPath = path
        browserLoading = true
        browserError = nil
        Task {
            do {
                let items = try await storage.list(path)
                guard browserPath == path else { return }
                browserFolders = items.filter { $0.isFolder && !$0.isHidden }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                browserHasObsidian = items.contains { $0.name == ".obsidian" }
            } catch {
                browserFolders = []
                browserHasObsidian = false
                browserError = error.localizedDescription
            }
            browserLoading = false
        }
    }

    func chooseRemoteFolder(_ path: String) {
        settings.remoteVaultPath = path
        isBrowsing = false
        verifyLocation()
    }

    /// Folder picker for a vault on this Mac. Starts in Obsidian's iCloud folder when there is one.
    func chooseLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as vault"
        panel.message = "Choose your Obsidian vault folder (the one that contains .obsidian)."
        panel.directoryURL = resolvedLocalFolder ?? LocalFolderStorage.obsidianICloudFolder ?? FileManager.default.homeDirectoryForCurrentUser
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.localBookmark = try? url.bookmarkData()
        settings.localPath = url.path
        verifyLocation()
    }

    /// Confirms the folder exists, whether it's an Obsidian vault, and that we can write to it
    /// (writes and removes a small hidden file).
    func verifyLocation() {
        guard let (provider, path) = vaultLocation else {
            locationCheck = .none
            return
        }
        locationCheck = .checking
        Task {
            do {
                guard try await provider.item(at: path) != nil else { throw StorageError.notFound(path) }
                let isVault = try await provider.item(at: StoragePath.join(path, ".obsidian")) != nil
                let probe = StoragePath.join(path, ".audiopencil-write-check")
                try await provider.write(probe, data: Data("ok".utf8), ifMatch: nil, createOnly: false)
                try await provider.delete(probe)
                locationCheck = .ok(isObsidianVault: isVault)
            } catch {
                locationCheck = .failed(error.localizedDescription)
            }
        }
    }

    /// "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Work" → "iCloud Drive › Obsidian › Work"
    var localPathDescription: String? {
        guard let path = settings.localPath else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let obsidian = home + "/Library/Mobile Documents/iCloud~md~obsidian/Documents"
        let iCloud = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if path.hasPrefix(obsidian) { return "iCloud Drive › Obsidian" + path.dropFirst(obsidian.count).replacingOccurrences(of: "/", with: " › ") }
        if path.hasPrefix(iCloud) { return "iCloud Drive" + path.dropFirst(iCloud.count).replacingOccurrences(of: "/", with: " › ") }
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}
