import APCore
import APModels
import APStorage
import APTranscription
import SwiftUI
import UniformTypeIdentifiers

struct PhoneSettingsView: View {
    @Bindable var app: PhoneModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        StorageSettingsView(vault: app.vault, sync: app.sync)
                    } label: {
                        LabeledContent("Storage", value: storageSummary)
                    }
                } footer: {
                    Text("Styles, vocabulary and tags come from the settings file there, shared with your Mac.")
                }
                Section {
                    NavigationLink { LanguagesSettingsView(app: app) } label: {
                        LabeledContent("Languages", value: app.offeredLanguages.map { $0.name() }.joined(separator: ", "))
                    }
                    NavigationLink { ModelsSettingsView(app: app) } label: {
                        LabeledContent("Models", value: "Whisper \(app.speechModelName)")
                    }
                    NavigationLink { StylesSettingsView(app: app) } label: {
                        LabeledContent("Styles", value: "\(app.enabledStyles.count)")
                    }
                }
                Section {
                    Button("Run Setup Again") { app.setupCompleted = false }
                } footer: {
                    Text("Private, on-device. Audio and text stay on this iPhone until you file a note in your own storage.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var storageSummary: String {
        guard app.vault.settings.isConfigured else { return String(localized: "Not set up") }
        return switch app.vault.settings.kind {
        case .nextcloud: "Nextcloud"
        case .webdav: "WebDAV"
        case .localFolder: app.vault.localPathDescription ?? String(localized: "Folder")
        }
    }
}

// MARK: Storage

/// Where notes and the settings file live: Nextcloud, any WebDAV server, or a folder in Files (which is
/// how an Obsidian vault in iCloud Drive is reached).
struct StorageSettingsView: View {
    @Bindable var vault: VaultController
    let sync: SyncController

    var body: some View {
        Form {
            StorageForm(vault: vault)
            if vault.settings.isConfigured {
                Section("Sync") {
                    LabeledContent("Status", value: syncStatus)
                    Button("Sync Now") { Task { await sync.syncNow() } }
                        .disabled(sync.status == .syncing)
                }
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var syncStatus: String {
        switch sync.status {
        case .syncing: String(localized: "Syncing…")
        case .idle: sync.lastSynced.map { String(localized: "Up to date, \($0.formatted(date: .omitted, time: .shortened))") } ?? String(localized: "Up to date")
        case .offline: String(localized: "Offline: changes wait here")
        case .paused(let message), .failed(let message): message
        case .notConfigured: String(localized: "Waiting for storage")
        }
    }
}

/// The storage choice and its sign-in and folder rows; shared by Settings and setup.
struct StorageForm: View {
    @Bindable var vault: VaultController
    @State private var importing = false
    @State private var user = ""
    @State private var password = ""
    @State private var address = ""
    @State private var useAppPassword = false

    var body: some View {
        Section {
            Picker("Where", selection: $vault.settings.kind) {
                Text("Nextcloud").tag(VaultSettings.Kind.nextcloud)
                Text("WebDAV").tag(VaultSettings.Kind.webdav)
                Text("Folder").tag(VaultSettings.Kind.localFolder)
            }
            .pickerStyle(.segmented)
            .onChange(of: vault.settings.kind) { vault.locationChanged() }
        } footer: {
            Text(kindDescription)
        }

        switch vault.settings.kind {
        case .nextcloud: nextcloud
        case .webdav: webdav
        case .localFolder: folder
        }

        if vault.settings.isConfigured {
            Section {
                locationStatus
            }
        }
    }

    private var kindDescription: LocalizedStringResource {
        switch vault.settings.kind {
        case .nextcloud: "Notes go to your Nextcloud over WebDAV, from any network."
        case .webdav: "Any server that speaks WebDAV: a Synology, ownCloud, a hosting provider."
        case .localFolder: "A folder in Files, such as your Obsidian vault in iCloud Drive (iCloud Drive › Obsidian)."
        }
    }

    @ViewBuilder
    private var nextcloud: some View {
        Section("Nextcloud account") {
            switch vault.connection {
            case .signedIn:
                LabeledContent("Signed in as", value: vault.settings.account?.loginName ?? "")
                Button("Sign Out", role: .destructive) { vault.signOut() }
            case .waitingForBrowser:
                HStack {
                    ProgressView()
                    Text("Approve Audio Pencil in Safari, then come back.")
                }
                Button("Cancel") { vault.cancelSignIn() }
            default:
                TextField("Server address", text: $vault.serverText, prompt: Text(verbatim: "cloud.example.com"))
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if useAppPassword {
                    TextField("Username", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("App password", text: $password)
                    Button("Connect") { vault.signIn(user: user, appPassword: password) }
                        .disabled(user.isEmpty || password.isEmpty || vault.serverText.isEmpty)
                } else {
                    Button("Sign In with Browser") { vault.signInWithBrowser() }
                        .disabled(vault.serverText.isEmpty || vault.connection == .checking)
                }
                Button(useAppPassword ? "Sign in with the browser instead" : "Use an app password instead") { useAppPassword.toggle() }
                    .font(.footnote)
                if case .failed(let message) = vault.connection {
                    Text(verbatim: message).font(.footnote).foregroundStyle(.orange)
                }
            }
        }
        if vault.connection == .signedIn { remoteFolder(vault.settings.remoteVaultPath) }
    }

    @ViewBuilder
    private var webdav: some View {
        Section("WebDAV server") {
            if vault.webdavConnection == .signedIn, let account = vault.settings.webdav {
                LabeledContent("Connected as", value: account.loginName)
                Text(verbatim: account.server.absoluteString).font(.footnote).foregroundStyle(.secondary)
                Button("Disconnect", role: .destructive) { vault.disconnectWebDAV() }
            } else {
                TextField("WebDAV address", text: $address, prompt: Text(verbatim: "https://example.com/dav/"))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Username", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password", text: $password)
                Button("Connect") { vault.connectWebDAV(url: address, user: user, password: password) }
                    .disabled(address.isEmpty || user.isEmpty || password.isEmpty || vault.webdavConnection == .checking)
                if case .failed(let message) = vault.webdavConnection {
                    Text(verbatim: message).font(.footnote).foregroundStyle(.orange)
                }
            }
        }
        if vault.webdavConnection == .signedIn { remoteFolder(vault.settings.webdavPath) }
    }

    private func remoteFolder(_ path: String?) -> some View {
        Section("Notes folder") {
            Button {
                vault.openBrowser()
            } label: {
                LabeledContent("Folder", value: path ?? String(localized: "Choose…"))
            }
            .sheet(isPresented: $vault.isBrowsing) {
                RemoteFolderBrowser(vault: vault)
            }
        }
    }

    private var folder: some View {
        Section("Notes folder") {
            Button {
                importing = true
            } label: {
                LabeledContent("Folder", value: vault.localPathDescription ?? String(localized: "Choose…"))
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { vault.useLocalFolder(url) }
            }
        }
    }

    @ViewBuilder
    private var locationStatus: some View {
        switch vault.locationCheck {
        case .none:
            EmptyView()
        case .checking:
            HStack { ProgressView(); Text("Checking…").foregroundStyle(.secondary) }
        case .ok(let isObsidianVault):
            Label(isObsidianVault ? "Obsidian vault · can write" as LocalizedStringResource : "Plain folder · can write", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label { Text(verbatim: message) } icon: { Image(systemName: "xmark.octagon.fill") }
                .foregroundStyle(.red)
        }
    }
}

/// Folder browser for Nextcloud or a WebDAV server.
struct RemoteFolderBrowser: View {
    @Bindable var vault: VaultController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if vault.browserHasObsidian {
                    Label("This folder is an Obsidian vault", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
                ForEach(vault.browserFolders) { folder in
                    Button {
                        vault.browse(folder.path)
                    } label: {
                        Label { Text(verbatim: folder.name) } icon: { Image(systemName: "folder.fill").foregroundStyle(Color.pencil) }
                    }
                    .tint(.primary)
                }
            }
            .overlay {
                if let error = vault.browserError {
                    Text(verbatim: error).foregroundStyle(.red).padding()
                } else if vault.browserLoading {
                    ProgressView()
                } else if vault.browserFolders.isEmpty {
                    Text("No folders here").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(vault.browserPath == "/" ? String(localized: "Files") : StorageItem(path: vault.browserPath, isFolder: true).name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button { vault.browse(StoragePath.parent(of: vault.browserPath)) } label: { Image(systemName: "chevron.up") }
                        .disabled(vault.browserPath == "/")
                        .accessibilityLabel("Up one folder")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") { vault.chooseRemoteFolder(vault.browserPath) }
                        .disabled(vault.browserPath == "/")
                }
            }
        }
    }
}

// MARK: Languages

struct LanguagesSettingsView: View {
    @Bindable var app: PhoneModel

    var body: some View {
        Form {
            LanguagesForm(app: app)
        }
        .navigationTitle("Languages")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The languages you dictate in, and which one the next recording starts in.
struct LanguagesForm: View {
    @Bindable var app: PhoneModel

    var body: some View {
        Section {
            ForEach(app.offeredLanguages) { language in
                HStack {
                    Text(language.name())
                    Spacer()
                    if language == app.currentLanguage {
                        Text("Next recording").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { app.useLanguage(language) }
            }
            .onDelete { offsets in
                let codes = app.offeredLanguages.map(\.code)
                let remaining = codes.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
                guard !remaining.isEmpty else { return }
                app.settings.dictationLanguages = remaining
                if !remaining.contains(app.currentLanguage.code) { app.useLanguage(SpokenLanguage(code: remaining[0])) }
            }
            Picker("Add a language", selection: Binding<String>(get: { "" }, set: { add($0) })) {
                Text("Choose…").tag("")
                ForEach(SpokenLanguage.all().filter { !app.offeredLanguages.contains($0) }) { Text($0.name()).tag($0.code) }
            }
        } header: {
            Text("Dictation languages")
        } footer: {
            Text("One language per recording: tap one to start the next recording in it, or switch with the language button while recording. English uses the English model; other languages use the multilingual one.")
        }
    }

    private func add(_ code: String) {
        guard !code.isEmpty else { return }
        app.settings.dictationLanguages = app.offeredLanguages.map(\.code) + [code]
    }
}

// MARK: Models

struct ModelsSettingsView: View {
    @Bindable var app: PhoneModel

    var body: some View {
        Form {
            Section {
                ModelStatusRow(app: app)
                if case .ready = app.modelState {
                    LabeledContent("In use", value: "Whisper \(app.speechModelName)")
                }
                Picker("English", selection: $app.settings.transcriptionModel) {
                    ForEach(TranscriptionModelOption.catalogue) { Text($0.name).tag($0.id) }
                }
                Picker("Other languages", selection: $app.settings.multilingualTranscriptionModel) {
                    ForEach(TranscriptionModelOption.multilingualCatalogue) { Text($0.name).tag($0.id) }
                }
            } header: {
                Text("Speech")
            } footer: {
                Text("Each model downloads once and is prepared for this iPhone's chip the first time it's used.")
            }
            Section {
                Picker("Model", selection: $app.settings.writingModel) {
                    ForEach(WritingModelOption.catalogue) { Text($0.name).tag($0.id) }
                }
                WritingModelRow(app: app)
            } header: {
                Text("Writing")
            } footer: {
                Text("Writes notes in your styles and suggests titles and tags. Without it, notes keep the transcript as spoken.")
            }
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WritingModelRow: View {
    let app: PhoneModel

    var body: some View {
        if !PhoneModel.canRunWritingModel {
            Text("The writing model runs on a real iPhone, not in the simulator.").font(.footnote).foregroundStyle(.secondary)
        } else if app.writingModelDownloaded {
            Label("On this iPhone", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else if case .downloading(let fraction) = app.writingModelState {
            HStack {
                ProgressView(value: fraction).tint(Color.pencil)
                Text("\(Int(fraction * 100))%").monospacedDigit().foregroundStyle(.secondary)
            }
        } else {
            Button {
                app.downloadWritingModel()
            } label: {
                Text("Download (\(ByteCountFormatter.string(fromByteCount: Int64((app.writingModelOption?.approximateDownloadGB ?? 1.7) * 1_000_000_000), countStyle: .file)))")
            }
            if case .failed(let message) = app.writingModelState {
                Text(verbatim: message).font(.footnote).foregroundStyle(.orange)
            }
        }
    }
}

// MARK: Styles

struct StylesSettingsView: View {
    @Bindable var app: PhoneModel

    var body: some View {
        Form {
            Section {
                ForEach($app.styles) { $style in
                    Toggle(isOn: $style.isEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: style.displayName)
                            Text(verbatim: style.displayDescription).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                    .disabled(style.isRaw)
                }
            } footer: {
                Text("Offered after each recording. Edit styles on your Mac; changes arrive here through the settings file.")
            }
        }
        .navigationTitle("Styles")
        .navigationBarTitleDisplayMode(.inline)
    }
}
