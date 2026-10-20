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
    /// The generic WebDAV server's sign-in state (Nextcloud's is `connection`).
    private(set) var webdavConnection: Connection = .signedOut
    private(set) var locationCheck: LocationCheck = .none
    /// A plain folder has become an Obsidian vault (it now has .obsidian): offer the review board.
    private(set) var obsidianUpgradeAvailable = false

    // Nextcloud folder browser
    var isBrowsing = false
    private(set) var browserPath = "/"
    private(set) var browserFolders: [StorageItem] = []
    private(set) var browserHasObsidian = false
    private(set) var browserLoading = false
    private(set) var browserError: String?

    @ObservationIgnored private var signInTask: Task<Void, Never>?
    /// Called when the vault folder has been checked and is usable.
    @ObservationIgnored var onLocationReady: (() -> Void)?
    /// Called when the layout changes (a new location, or a plain folder adopted as an Obsidian vault).
    @ObservationIgnored var onLayoutChanged: (() -> Void)?

    /// How notes are written here. Nil until the location has been checked once.
    var layout: NoteLayout? { settings.layout }

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
        if let webdav = settings.webdav, Keychain.password(for: webdav) != nil {
            webdavConnection = .signedIn
        }
        if settings.isConfigured { verifyLocation() }
        if connection == .signedIn, let server = settings.account?.server {
            Task {
                if let status = try? await NextcloudServer.status(of: server) {
                    serverDescription = [status.productname, status.versionstring].compactMap { $0 }.joined(separator: " ")
                }
            }
        }
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
            connection = .failed(String(localized: "Enter your Nextcloud address, like cloud.example.com."))
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
            connection = .failed(String(localized: "Enter your Nextcloud address, like cloud.example.com."))
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

    private var webdavStorage: WebDAVStorage? {
        guard let account = settings.webdav, let password = Keychain.password(for: account) else { return nil }
        return WebDAVStorage(davRoot: account.server, loginName: account.loginName, password: password)
    }

    /// The server the folder browser works on: Nextcloud or the generic WebDAV server.
    private var remoteStorage: WebDAVStorage? {
        settings.kind == .webdav ? webdavStorage : nextcloudStorage
    }

    // MARK: Any WebDAV server

    /// Checks the server answers WebDAV with these credentials, then remembers them (password in the Keychain).
    func connectWebDAV(url text: String, user: String, password: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host() != nil
        else {
            webdavConnection = .failed(String(localized: "Enter the server's WebDAV address, like https://example.com/dav/."))
            return
        }
        let account = NextcloudAccount(server: url, loginName: user.trimmingCharacters(in: .whitespaces))
        webdavConnection = .checking
        Task {
            do {
                let storage = WebDAVStorage(davRoot: url, loginName: account.loginName, password: password)
                guard try await storage.item(at: "/") != nil else { throw StorageError.notFound(url.absoluteString) }
                try Keychain.savePassword(password, for: account, service: "WebDAV")
                if settings.webdav != account { settings.webdavPath = nil }
                settings.webdav = account
                webdavConnection = .signedIn
                locationChanged()
            } catch {
                webdavConnection = .failed(error.localizedDescription)
            }
        }
    }

    func disconnectWebDAV() {
        if let account = settings.webdav { Keychain.deletePassword(for: account) }
        settings.webdav = nil
        settings.webdavPath = nil
        webdavConnection = .signedOut
        locationCheck = .none
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
        case .webdav:
            guard let storage = webdavStorage, let path = settings.webdavPath else { return nil }
            return (storage, path)
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
        let current = settings.kind == .webdav ? settings.webdavPath : settings.remoteVaultPath
        browse(current.map(StoragePath.parent) ?? "/")
    }

    func browse(_ path: String) {
        guard let storage = remoteStorage else { return }
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
        if settings.kind == .webdav {
            settings.webdavPath = path
        } else {
            settings.remoteVaultPath = path
        }
        isBrowsing = false
        locationChanged()
    }

    /// A vault-relative path as a file on this Mac (local and iCloud folders only).
    func localFileURL(for path: String) -> URL? {
        guard settings.kind == .localFolder, let root = resolvedLocalFolder else { return nil }
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return relative.isEmpty ? root : root.appending(path: relative)
    }

    /// Sync saw a .obsidian folder appear in a plain folder.
    func noticeObsidianFolder() {
        if settings.layout == .plain { obsidianUpgradeAvailable = true }
    }

    /// A different place: its layout is worked out afresh when it's checked.
    func locationChanged() {
        settings.layout = nil
        obsidianUpgradeAvailable = false
        verifyLocation()
    }

    /// The plain folder became an Obsidian vault and the user wants the board: write notes for Obsidian from now on.
    func adoptObsidianLayout() {
        settings.layout = .obsidian
        obsidianUpgradeAvailable = false
        onLayoutChanged?()
    }

    /// A folder on this Mac becomes the storage (setup's "vaults on this Mac", or the folder picker).
    func useLocalFolder(_ url: URL) {
        settings.kind = .localFolder
        settings.localBookmark = try? url.bookmarkData()
        settings.localPath = url.path
        locationChanged()
    }

    /// Folder picker for a vault on this Mac. Starts in Obsidian's iCloud folder when there is one.
    func chooseLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Use this folder")
        panel.message = String(localized: "Choose the folder for your notes. An Obsidian vault (with a .obsidian folder) also gets a review board.")
        panel.directoryURL = resolvedLocalFolder ?? LocalFolderStorage.obsidianICloudFolder ?? FileManager.default.homeDirectoryForCurrentUser
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        useLocalFolder(url)
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
                // Off the main thread: a folder in iCloud Drive can make macOS ask for access, and the
                // file calls wait for the answer.
                let isVault = try await Task.detached { try await Self.check(provider, path) }.value
                locationCheck = .ok(isObsidianVault: isVault)
                switch (settings.layout, isVault) {
                case (nil, _):
                    settings.layout = isVault ? .obsidian : .plain
                    onLayoutChanged?()
                case (.plain?, true):
                    obsidianUpgradeAvailable = true // never adds files without asking
                default:
                    obsidianUpgradeAvailable = false
                }
                onLocationReady?()
            } catch {
                locationCheck = .failed(error.localizedDescription)
            }
        }
    }

    /// The folder exists and takes writes (a small hidden file, written and removed). Returns whether
    /// it's an Obsidian vault.
    nonisolated private static func check(_ provider: any StorageProvider, _ path: String) async throws -> Bool {
        guard try await provider.item(at: path) != nil else { throw StorageError.notFound(path) }
        let isVault = try await provider.item(at: StoragePath.join(path, ".obsidian")) != nil
        let probe = StoragePath.join(path, ".audiopencil-write-check")
        try await provider.write(probe, data: Data("ok".utf8), ifMatch: nil, createOnly: false)
        try await provider.delete(probe)
        return isVault
    }

    /// The Obsidian vault's name: its folder's name.
    var vaultName: String? {
        let path = switch settings.kind {
        case .nextcloud: settings.remoteVaultPath
        case .localFolder: settings.localPath
        case .webdav: settings.webdavPath
        }
        return path?.split(separator: "/").last.map(String.init)
    }

    /// "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Work" → "iCloud Drive › Obsidian › Work"
    var localPathDescription: String? {
        settings.localPath.map(Self.describe)
    }

    static func describe(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let obsidian = home + "/Library/Mobile Documents/iCloud~md~obsidian/Documents"
        let iCloud = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if path.hasPrefix(obsidian) { return "iCloud Drive › Obsidian" + path.dropFirst(obsidian.count).replacingOccurrences(of: "/", with: " › ") }
        if path.hasPrefix(iCloud) { return "iCloud Drive" + path.dropFirst(iCloud.count).replacingOccurrences(of: "/", with: " › ") }
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}
