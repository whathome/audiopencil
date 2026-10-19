import APStorage
import APSync
import SwiftUI

/// Where notes and settings will live: Nextcloud or a folder on this Mac (e.g. iCloud Drive).
struct VaultPage: View {
    @Bindable var vault: VaultController
    let sync: SyncController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Vault", subtitle: "Your Obsidian vault: where notes and Audio Pencil's settings will live.")

                Card(title: "Storage") {
                    Picker("", selection: $vault.settings.kind) {
                        Label("Nextcloud", systemImage: "cloud").tag(VaultSettings.Kind.nextcloud)
                        Label("Folder on this Mac", systemImage: "folder").tag(VaultSettings.Kind.localFolder)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: vault.settings.kind) { vault.verifyLocation() }
                    Text(vault.settings.kind == .nextcloud
                        ? "Notes go to your Nextcloud over WebDAV, from any network. Nothing else leaves this Mac."
                        : "Use a vault already synced to this Mac, such as an Obsidian vault in iCloud Drive. iCloud does the syncing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if vault.settings.kind == .nextcloud {
                    NextcloudAccountCard(vault: vault)
                    if vault.connection == .signedIn {
                        LocationCard(vault: vault) {
                            Text(vault.settings.remoteVaultPath ?? "Not chosen")
                                .font(.body.monospaced())
                        } choose: {
                            vault.openBrowser()
                        }
                    }
                } else {
                    LocationCard(vault: vault) {
                        Text(vault.localPathDescription ?? "Not chosen")
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
            NextcloudFolderBrowser(vault: vault)
        }
    }
}

private struct SyncCard: View {
    let sync: SyncController

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
                Button("Sync now") { Task { await sync.syncNow() } }
                    .disabled(sync.status == .syncing)
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
                    Text(sync.queuedUploads == 0 ? "Nothing" : "\(sync.queuedUploads) item\(sync.queuedUploads == 1 ? "" : "s")")
                }
            }
            .font(.callout)
            Text("Styles, vocabulary and tags are shared through the settings file; edit it in Obsidian and changes arrive here within a minute. This Mac's hotkey, microphone and model choices live in its own section.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var statusTitle: String {
        switch sync.status {
        case .syncing: "Syncing…"
        case .idle: "Up to date"
        case .offline: "Offline: changes wait here and sync when you're back"
        case .paused: "Paused: fix the settings file in Obsidian"
        case .failed: "Couldn't sync"
        case .notConfigured: "Waiting for the vault"
        }
    }

    private var statusDetail: String? {
        switch sync.status {
        case .idle: sync.lastSynced.map { "Last synced \($0.formatted(date: .omitted, time: .shortened))" }
        case .paused(let message), .failed(let message): message
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

private struct LocationCard<Path: View>: View {
    let vault: VaultController
    @ViewBuilder var path: Path
    let choose: () -> Void

    var body: some View {
        Card(title: "Vault folder") {
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
                    Label("Can write here, but there's no .obsidian folder. Is this the vault's top folder?", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }
        }
    }
}

private struct NextcloudFolderBrowser: View {
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
                Text(vault.browserPath == "/" ? "Files" : vault.browserPath)
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
                Button("Use “\(vault.browserPath == "/" ? "Files" : StorageItem(path: vault.browserPath, isFolder: true).name)”") {
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
