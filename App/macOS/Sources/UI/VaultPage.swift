import APStorage
import APSync
import SwiftUI

/// Where notes and settings live: Nextcloud, any WebDAV server, or a folder on this Mac (e.g. iCloud Drive).
/// An Obsidian vault gets the extras (board, guide); any other folder gets plain Markdown.
struct VaultPage: View {
    @Bindable var vault: VaultController
    let sync: SyncController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Storage", subtitle: "Where notes and Audio Pencil's settings live: an Obsidian vault, or any folder.")

                Card(title: "Where") {
                    Picker("", selection: $vault.settings.kind) {
                        Label("Nextcloud", systemImage: "cloud").tag(VaultSettings.Kind.nextcloud)
                        Label("WebDAV", systemImage: "server.rack").tag(VaultSettings.Kind.webdav)
                        Label("Folder on this Mac", systemImage: "folder").tag(VaultSettings.Kind.localFolder)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize() // a short choice, not a tab bar across the card
                    .onChange(of: vault.settings.kind) { vault.locationChanged() }
                    Text(kindDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if vault.settings.kind == .nextcloud {
                    NextcloudAccountCard(vault: vault)
                    if vault.connection == .signedIn {
                        LocationCard(vault: vault) {
                            Text(vault.settings.remoteVaultPath.map { "\($0)" } ?? "Not chosen" as LocalizedStringResource)
                                .font(.body.monospaced())
                        } choose: {
                            vault.openBrowser()
                        }
                    }
                } else if vault.settings.kind == .webdav {
                    WebDAVAccountCard(vault: vault)
                    if vault.webdavConnection == .signedIn {
                        LocationCard(vault: vault) {
                            Text(vault.settings.webdavPath.map { "\($0)" } ?? "Not chosen" as LocalizedStringResource)
                                .font(.body.monospaced())
                        } choose: {
                            vault.openBrowser()
                        }
                    }
                } else {
                    LocationCard(vault: vault) {
                        Text(vault.localPathDescription.map { "\($0)" } ?? "Not chosen" as LocalizedStringResource)
                            .font(.body.monospaced())
                            .help(vault.settings.localPath ?? "")
                    } choose: {
                        vault.chooseLocalFolder()
                    }
                }

                if vault.settings.isConfigured {
                    SyncCard(sync: sync)
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .sheet(isPresented: $vault.isBrowsing) {
            RemoteFolderBrowser(vault: vault)
        }
    }

    private var kindDescription: LocalizedStringResource {
        switch vault.settings.kind {
        case .nextcloud: "Notes go to your Nextcloud over WebDAV, from any network. Nothing else leaves this Mac."
        case .webdav: "Any server that speaks WebDAV: a Synology, ownCloud, a hosting provider. Nothing else leaves this Mac."
        case .localFolder: "A folder on this Mac, or one synced to it such as iCloud Drive. Your sync service does the syncing."
        }
    }
}

private struct SyncCard: View {
    let sync: SyncController
    @State private var confirmingRepair = false

    var body: some View {
        Card(title: "Sync") {
            HStack(spacing: 10) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle).font(.headline)
                    if let detail = statusDetail {
                        Text(detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                Spacer()
                if case .paused = sync.status {
                    Button("Repair…") { confirmingRepair = true }
                }
                Button("Sync now") { Task { await sync.syncNow() } }
                    .disabled(sync.status == .syncing)
            }
            if let summary = sync.repairSummary {
                HStack(alignment: .top) {
                    Label(summary, systemImage: "wrench.and.screwdriver").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button { sync.clearRepairSummary() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Dismiss")
                }
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Settings file").foregroundStyle(.secondary)
                    Text(sync.settingsFilePath ?? "–").font(.callout.monospaced()).textSelection(.enabled)
                }
                GridRow {
                    Text("This device").foregroundStyle(.secondary)
                    Text(sync.deviceName)
                }
                GridRow {
                    Text("Waiting to upload").foregroundStyle(.secondary)
                    Text(sync.queuedUploads == 0 ? "Nothing" as LocalizedStringResource : "\(sync.queuedUploads) items")
                }
            }
            .font(.callout)
            Text("Styles, vocabulary and tags are shared through the settings file; edit it in Obsidian and changes arrive here within a minute. This Mac's hotkey, microphone and model choices live in its own section.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog("Repair the settings file?", isPresented: $confirmingRepair) {
            Button("Repair") { Task { await sync.repairSettings() } }
        } message: {
            Text("Every section that still reads correctly is kept, including edits made elsewhere. Only the broken parts are put back from the last good version. A copy of the file as it is now goes to Audio Pencil/Backups first. If you're still editing it in Obsidian, finish that instead.")
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch sync.status {
        case .syncing: ProgressView().controlSize(.small)
        case .idle: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .offline: Image(systemName: "wifi.slash").foregroundStyle(.secondary)
        case .paused: Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .notConfigured: Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }

    private var statusTitle: LocalizedStringResource {
        switch sync.status {
        case .syncing: "Syncing…"
        case .idle: "Up to date"
        case .offline: "Offline: changes wait here and sync when you're back"
        case .paused: "Paused: fix the settings file in Obsidian"
        case .failed: "Couldn't sync"
        case .notConfigured: "Waiting for storage"
        }
    }

    private var statusDetail: LocalizedStringResource? {
        switch sync.status {
        case .idle: sync.lastSynced.map { "Last synced \($0.formatted(date: .omitted, time: .shortened))" }
        case .paused(let message), .failed(let message): "\(message)"
        default: nil
        }
    }
}

private struct NextcloudAccountCard: View {
    @Bindable var vault: VaultController
    @State private var useAppPassword = false
    @State private var user = ""
    @State private var appPassword = ""

    var body: some View {
        Card(title: "Nextcloud account") {
            switch vault.connection {
            case .signedIn:
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in as \(vault.settings.account?.loginName ?? "")").font(.headline)
                        Text([vault.settings.account?.server.host(), vault.serverDescription].compactMap { $0 }.joined(separator: " · "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sign out", role: .destructive) { vault.signOut() }
                }
            case .waitingForBrowser(let url):
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Approve Audio Pencil in your browser").font(.headline)
                        Text("Log in to Nextcloud there and grant access. This window updates by itself.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open again") { NSWorkspace.shared.open(url) }
                    Button("Cancel") { vault.cancelSignIn() }
                }
            default:
                signInForm
            }
        }
    }

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Server address", text: $vault.serverText, prompt: Text("cloud.example.com"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                    .onSubmit { if !useAppPassword { vault.signInWithBrowser() } }
                if vault.connection == .checking {
                    ProgressView().controlSize(.small)
                }
            }
            if useAppPassword {
                HStack {
                    TextField("Username", text: $user).textFieldStyle(.roundedBorder).frame(maxWidth: 170)
                    SecureField("App password", text: $appPassword).textFieldStyle(.roundedBorder).frame(maxWidth: 182)
                    Button("Connect") { vault.signIn(user: user, appPassword: appPassword) }
                        .disabled(user.isEmpty || appPassword.isEmpty || vault.serverText.isEmpty)
                }
                Text("Create one in Nextcloud under Settings › Security › Devices & sessions.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button {
                    vault.signInWithBrowser()
                } label: {
                    Label("Sign in with browser", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vault.serverText.isEmpty || vault.connection == .checking)
            }
            if case .failed(let message) = vault.connection {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Button(useAppPassword ? "Sign in with the browser instead" : "Use an app password instead") {
                useAppPassword.toggle()
            }
            .buttonStyle(.link)
            .font(.callout)
        }
    }
}

private struct WebDAVAccountCard: View {
    let vault: VaultController
    @State private var address = ""
    @State private var user = ""
    @State private var password = ""

    var body: some View {
        Card(title: "WebDAV server") {
            if vault.webdavConnection == .signedIn, let account = vault.settings.webdav {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected as \(account.loginName)").font(.headline)
                        Text(verbatim: account.server.absoluteString).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Disconnect", role: .destructive) { vault.disconnectWebDAV() }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("WebDAV address", text: $address, prompt: Text(verbatim: "https://example.com/dav/"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                    HStack {
                        TextField("Username", text: $user).textFieldStyle(.roundedBorder).frame(maxWidth: 170)
                        SecureField("Password", text: $password).textFieldStyle(.roundedBorder).frame(maxWidth: 182)
                        Button("Connect") { vault.connectWebDAV(url: address, user: user, password: password) }
                            .disabled(address.isEmpty || user.isEmpty || password.isEmpty || vault.webdavConnection == .checking)
                        if vault.webdavConnection == .checking {
                            ProgressView().controlSize(.small)
                        }
                    }
                    Text("The password stays in this Mac's Keychain. Use an app-specific password if your server offers one.")
                        .font(.caption).foregroundStyle(.secondary)
                    if case .failed(let message) = vault.webdavConnection {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                .onAppear {
                    if let account = vault.settings.webdav {
                        address = account.server.absoluteString
                        user = account.loginName
                    }
                }
            }
        }
    }
}

private struct LocationCard<Path: View>: View {
    let vault: VaultController
    @ViewBuilder var path: Path
    let choose: () -> Void

    var body: some View {
        Card(title: "Notes folder") {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill").foregroundStyle(Color.pencil)
                path
                Spacer()
                Button("Choose…", action: choose)
            }
            switch vault.locationCheck {
            case .none:
                EmptyView()
            case .checking:
                HStack { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
            case .ok(let isObsidianVault):
                if isObsidianVault {
                    Label("Obsidian vault · can write", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("Plain folder · can write", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    if vault.obsidianUpgradeAvailable {
                        HStack {
                            Text("This folder is now an Obsidian vault. Add the review board and guide?")
                                .font(.callout)
                            Spacer()
                            Button("Add board") { vault.adoptObsidianLayout() }
                        }
                    } else {
                        Text("Notes are standard Markdown with a link to their recording. If this is meant to be an Obsidian vault, choose its top folder, the one holding .obsidian.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }
        }
    }
}

/// Folder browser for Nextcloud or a WebDAV server.
private struct RemoteFolderBrowser: View {
    @Bindable var vault: VaultController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    vault.browse(StoragePath.parent(of: vault.browserPath))
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(vault.browserPath == "/")
                .accessibilityLabel("Up one folder")
                Text(vault.browserPath == "/" ? "Files" as LocalizedStringResource : "\(vault.browserPath)")
                    .font(.headline.monospaced())
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                if vault.browserLoading { ProgressView().controlSize(.small) }
            }
            .padding(12)
            Divider()

            if vault.browserHasObsidian {
                Label("This folder is an Obsidian vault", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
            }

            List(vault.browserFolders) { folder in
                Button {
                    vault.browse(folder.path)
                } label: {
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(Color.pencil)
                        Text(folder.name)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if let error = vault.browserError {
                    Text(error).foregroundStyle(.red).padding()
                } else if vault.browserFolders.isEmpty, !vault.browserLoading {
                    Text("No folders here").foregroundStyle(.secondary)
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use “\(vault.browserPath == "/" ? String(localized: "Files") : StorageItem(path: vault.browserPath, isFolder: true).name)”") {
                    vault.chooseRemoteFolder(vault.browserPath)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vault.browserPath == "/")
            }
            .padding(12)
        }
        .frame(width: 520, height: 460)
    }
}
