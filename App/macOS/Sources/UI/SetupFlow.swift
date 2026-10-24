import APCore
import APModels
import APStorage
import APTranscription
import SwiftUI

enum SetupStep: Int, CaseIterable {
    case welcome, permissions, languages, storage, models, ready

    var name: LocalizedStringResource {
        switch self {
        case .welcome: "Welcome"
        case .permissions: "Permissions"
        case .languages: "Languages"
        case .storage: "Storage"
        case .models: "Models"
        case .ready: "Getting ready"
        }
    }
}

/// The guided setup window: six short steps. Models download and prepare in the background from the
/// Permissions step on, so by the end English dictation is usually ready to try.
struct SetupFlow: View {
    @Bindable var app: AppModel
    /// Closes the window; closing finishes setup and brings up the main window.
    let close: () -> Void
    @State private var wantsWriting = true

    private var step: SetupStep {
        get { app.setupStep }
        nonmutating set { app.setupStep = newValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            StepTrack(step: step)
                .padding(.top, 30) // under the transparent title bar's traffic lights
                .padding(.horizontal, 40)
            ScrollView {
                content
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 680, height: 640)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .permissions: PermissionsStep(app: app)
        case .languages: LanguagesStep(app: app)
        case .storage: StorageStep(vault: app.vault)
        case .models: ModelsStep(app: app, wantsWriting: $wantsWriting)
        case .ready: ReadyStep(app: app, wantsWriting: wantsWriting)
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome, step != .ready {
                Button("Back") { move(-1) }
            }
            Spacer()
            if step == .storage, !app.vault.settings.isConfigured {
                Button("Skip for Now") { move(1) }
            }
            Button(action: next) { Text(primaryTitle) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(step == .storage && !app.vault.settings.isConfigured)
        }
        .controlSize(.large)
    }

    private var primaryTitle: LocalizedStringResource {
        switch step {
        case .welcome: "Get Started"
        case .models: "Get Ready"
        case .ready: "Open Audio Pencil"
        default: "Continue"
        }
    }

    private func next() {
        switch step {
        case .models:
            app.startSetupDownloads(writing: wantsWriting)
            move(1)
        case .ready:
            close()
        default:
            move(1)
        }
    }

    private func move(_ delta: Int) {
        guard let target = SetupStep(rawValue: step.rawValue + delta) else { return }
        step = target
    }
}

/// Where you are: one short bar per step, filled up to the current one.
private struct StepTrack: View {
    let step: SetupStep

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(SetupStep.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.pencil : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            Text("Step \(step.rawValue + 1) of \(SetupStep.allCases.count): \(String(localized: step.name))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StepHeader: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 26, weight: .bold, design: .serif))
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 6)
    }
}

// MARK: 1. Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
                .padding(.leading, -8) // the icon's own transparent margin; line its edge up with the text
                .accessibilityHidden(true)
            StepHeader(title: "Welcome to Audio Pencil", subtitle: "Talk anywhere on your Mac. Your words land where you're typing, written by models that run on this Mac.")
            VStack(alignment: .leading, spacing: 16) {
                Point(symbol: "keyboard", title: "Dictate into any app", detail: "Tap a key, talk, and the text appears in whatever you're writing: tidied up, or rewritten in a style you choose.")
                Point(symbol: "lock", title: "Private by design", detail: "Speech recognition and writing happen on this Mac. What you say isn't sent anywhere.")
                Point(symbol: "doc.text", title: "Long thoughts become notes", detail: "Longer recordings are saved as Markdown notes with their audio, in Obsidian or any folder.")
            }
            Text("Setup takes a couple of minutes. Models download and get ready while you go.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }

    private struct Point: View {
        let symbol: String
        let title: LocalizedStringResource
        let detail: LocalizedStringResource

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(Color.pencil)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: 2. Permissions

private struct PermissionsStep: View {
    @Bindable var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Your dictation key", subtitle: "Pick how you start dictating, then let Audio Pencil hear you and type for you.")
            Card(title: "Start dictating with") {
                HStack(spacing: 10) {
                    Picker("Key", selection: $app.settings.gestureKey) {
                        ForEach(GestureKey.allCases, id: \.self) { Text(verbatim: $0.name).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Picker("Gesture", selection: $app.settings.startGesture) {
                        ForEach(StartGesture.allCases, id: \.self) { Text(verbatim: $0.label(app.settings.gestureKey)).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                }
                Text(app.settings.startGesture == .doubleTap
                     ? "Double-tap to start, tap again to stop and paste. Esc cancels. More choices are in Settings."
                     : "Tap to start, tap again to stop and paste. Esc cancels. More choices are in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Card(title: "Permissions") {
                VStack(alignment: .leading, spacing: 12) {
                    PermissionRow(
                        title: "Microphone",
                        detail: "To hear you while you dictate.",
                        granted: app.permissions.microphone == .granted,
                        action: ("Allow…", { Task { await app.permissions.requestMicrophone() } })
                    )
                    PermissionRow(
                        title: "Accessibility",
                        detail: "To notice the dictation key and paste into the app you're using.",
                        granted: app.permissions.accessibility,
                        action: ("Allow…", { app.permissions.requestAccessibility() })
                    )
                    if app.settings.gestureKey == .fn {
                        PermissionRow(
                            title: "Fn key free",
                            detail: app.permissions.fnKeyIsFree
                                ? "“Press 🌐 key to” is set to Do Nothing." as LocalizedStringResource
                                : "“Press 🌐 key to” is set to \(app.permissions.fnKeyActionDescription). Set it to Do Nothing so Fn only starts dictation.",
                            granted: app.permissions.fnKeyIsFree,
                            action: ("Keyboard Settings…", { app.permissions.openKeyboardSettings() })
                        )
                    }
                }
            }
            if !app.permissions.allRequiredGranted {
                Text("You can carry on and finish these later in Settings › Permissions. Until then the key won't start dictation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { app.startSetupModel() }
    }
}

// MARK: 3. Languages

private struct LanguagesStep: View {
    @Bindable var app: AppModel
    /// Shown as checkboxes: what's chosen, plus this Mac's own languages. Fixed while the step is open
    /// so unticking one doesn't make it vanish.
    @State private var candidates: [SpokenLanguage] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Which languages do you speak?", subtitle: "Each recording is in one language. Choose every language you'll dictate in; you can switch between them from the recording indicator.")
            Card(title: "Dictation languages") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(candidates + chosen.filter { !candidates.contains($0) }) { language in
                        Toggle(isOn: binding(for: language)) {
                            HStack(spacing: 6) {
                                Text(language.name())
                                if chosen.contains(language), !app.canStyle(in: language) {
                                    Text("Raw transcripts only with \(app.writingModelOption?.name ?? "this writing model")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Picker("Add another language", selection: Binding<String>(get: { "" }, set: { add($0) })) {
                    Text("Choose…").tag("")
                    ForEach(SpokenLanguage.all().filter { !candidates.contains($0) }) { Text($0.name()).tag($0.code) }
                }
                .fixedSize()
            }
            if chosen.count > 1 {
                Card(title: "Start in") {
                    Picker("New apps start in", selection: Binding(
                        get: { app.languageMemory.language(forApp: nil) },
                        set: { app.chooseDefaultLanguage($0) }
                    )) {
                        ForEach(chosen) { Text($0.name()).tag($0) }
                    }
                    .fixedSize()
                    Text("After that, each app remembers the language you last spoke in it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if chosen.contains(where: { !$0.isEnglish }) {
                Text("Languages other than English use a multilingual speech model. It downloads in the background; the next steps show how long it takes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            guard candidates.isEmpty else { return }
            let system = Locale.preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
            let known = Set(SpokenLanguage.all().map(\.code))
            var codes = app.offeredLanguages.map(\.code)
            for code in system where known.contains(code) && !codes.contains(code) { codes.append(code) }
            candidates = codes.map(SpokenLanguage.init)
        }
    }

    private var chosen: [SpokenLanguage] { app.offeredLanguages }

    private func binding(for language: SpokenLanguage) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(language) },
            set: { on in
                if on {
                    app.settings.dictationLanguages = chosen.map(\.code) + [language.code]
                } else if chosen.count > 1 {
                    let remaining = chosen.map(\.code).filter { $0 != language.code }
                    app.settings.dictationLanguages = remaining
                    if app.languageMemory.language(forApp: nil) == language || app.activeLanguage == language {
                        app.chooseDefaultLanguage(SpokenLanguage(code: remaining[0]))
                    }
                }
            }
        )
    }

    private func add(_ code: String) {
        guard !code.isEmpty else { return }
        let language = SpokenLanguage(code: code)
        candidates.append(language)
        app.settings.dictationLanguages = chosen.map(\.code) + [code]
    }
}

// MARK: 4. Storage

private struct StorageStep: View {
    @Bindable var vault: VaultController
    @State private var found: [FoundVault] = []
    /// Nextcloud or WebDAV, once the user picks one of them here.
    @State private var remote: VaultSettings.Kind?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Where should notes go?", subtitle: "Long recordings become notes, and Audio Pencil keeps a small settings file next to them so your Macs share styles and vocabulary.")
            if !found.isEmpty {
                Card(title: "Obsidian vaults on this Mac") {
                    VStack(spacing: 0) {
                        ForEach(found) { item in
                            Button { choose(item) } label: { FoundVaultRow(vault: item, selected: isSelected(item)) }
                                .buttonStyle(.plain)
                            if item != found.last { Divider() }
                        }
                    }
                }
            }
            Card(title: found.isEmpty ? "Choose a place" : "Somewhere else") {
                HStack(spacing: 8) {
                    Button { remote = nil; vault.settings.kind = .localFolder; vault.chooseLocalFolder() } label: {
                        Label("Choose a Folder…", systemImage: "folder")
                    }
                    Button { pickRemote(.nextcloud) } label: { Label("Nextcloud", systemImage: "cloud") }
                    Button { pickRemote(.webdav) } label: { Label("WebDAV", systemImage: "server.rack") }
                }
                Text("Any folder works, Obsidian or not; iCloud Drive and other synced folders too. An Obsidian vault also gets a review board.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if remote != nil, vault.settings.kind == remote {
                StorageLocationCards(vault: vault)
            } else if vault.settings.kind == .localFolder, vault.settings.isConfigured {
                localStatus
            }
            if vault.settings.isConfigured, case .ok(let isObsidianVault) = vault.locationCheck {
                Text(isObsidianVault
                     ? "Audio Pencil adds an Audio Pencil folder here with a review board, a short guide, three sample notes and the settings file."
                     : "Audio Pencil adds an Audio Pencil folder here with the settings file and a note explaining the files. Notes are plain Markdown.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !vault.settings.isConfigured {
                Text("You can skip this: notes wait on this Mac until you choose a place on the Storage page.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if vault.settings.isConfigured, vault.settings.kind != .localFolder { remote = vault.settings.kind }
        }
        .task { found = await Task.detached { ObsidianVaults.find() }.value }
    }

    @ViewBuilder
    private var localStatus: some View {
        HStack(spacing: 8) {
            switch vault.locationCheck {
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            case .ok(let isObsidianVault):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(isObsidianVault ? "Obsidian vault · can write" as LocalizedStringResource : "Plain folder · can write")
            case .failed(let message):
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                Text(verbatim: message)
            case .none:
                EmptyView()
            }
            Spacer()
            if let path = vault.localPathDescription {
                Text(verbatim: path).font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
        }
        .font(.callout)
    }

    private func isSelected(_ item: FoundVault) -> Bool {
        vault.settings.kind == .localFolder && vault.settings.localPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path } == item.url.path
    }

    private func choose(_ item: FoundVault) {
        remote = nil
        vault.useLocalFolder(item.url)
    }

    private func pickRemote(_ kind: VaultSettings.Kind) {
        remote = kind
        if vault.settings.kind != kind {
            vault.settings.kind = kind
            vault.locationChanged()
        }
    }
}

private struct FoundVaultRow: View {
    let vault: FoundVault
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "books.vertical").foregroundStyle(Color.pencil).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: vault.name).font(.body.weight(.medium))
                Text(verbatim: VaultController.describe(vault.url.path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.pencil : Color.secondary)
                .imageScale(.large)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: 5. Models

private struct ModelsStep: View {
    let app: AppModel
    @Binding var wantsWriting: Bool

    var body: some View {
        let models = app.setupModels(includingWriting: wantsWriting)
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Models for this Mac", subtitle: "Everything runs on this Mac, so it needs a few models. They download once and get prepared for this Mac's chip, in the background.")
            Card(title: "Speech") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(models.filter { $0.kind != .writing }) { ModelLine(model: $0) }
                }
            }
            Card(title: "Writing") {
                Toggle(isOn: $wantsWriting) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rewrite in styles with \(app.writingModelOption?.name ?? "the writing model")")
                        if let option = app.writingModelOption, !app.writingModelDownloaded {
                            Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(option.approximateDownloadGB * 1_000_000_000), countStyle: .file))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text("Turns dictation into polished text, emails or notes, and gives long recordings a title and summary. Without it, text is pasted as you said it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
            }
            Text(summary(models))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "About 2.6 GB to download. Preparing takes about 14 min the first time on this Mac (Apple M1, 8 GB) …"
    private func summary(_ models: [SetupModel]) -> String {
        let megabytes = models.filter { !$0.downloaded }.map(\.downloadMB).reduce(0, +)
        let size = ByteCountFormatter.string(fromByteCount: Int64(megabytes) * 1_000_000, countStyle: .file)
        let minutes = Int((models.compactMap(\.prepareSeconds).reduce(0, +) / 60).rounded(.up))
        let machine = MachineProfile.current
        let mac = "\(machine.chip), \(Int(machine.memoryGB.rounded())) GB"
        return switch (megabytes > 0, minutes > 0) {
        case (true, true): String(localized: "About \(size) to download. Preparing takes about \(minutes) min the first time on this Mac (\(mac)), and never again. English dictation works as soon as its own model is ready.")
        case (false, true): String(localized: "Already downloaded. Preparing takes about \(minutes) min the first time on this Mac (\(mac)), and never again.")
        case (true, false): String(localized: "About \(size) to download.")
        case (false, false): String(localized: "Everything is already on this Mac.")
        }
    }
}

/// One model: what it's for, its download size and how long it takes to prepare.
private struct ModelLine: View {
    let model: SetupModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: model.name).font(.body.weight(.medium))
                Text(verbatim: model.purpose).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: facts).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var facts: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(model.downloadMB) * 1_000_000, countStyle: .file)
        guard let seconds = model.prepareSeconds else { return model.downloaded ? String(localized: "On this Mac") : size }
        let time = seconds < 90
            ? String(localized: "about \(Int(seconds.rounded())) s")
            : String(localized: "about \(Int((seconds / 60).rounded())) min")
        return model.downloaded ? String(localized: "Prepares in \(time)") : String(localized: "\(size) · prepares in \(time)")
    }
}

// MARK: 6. Getting ready

private struct ReadyStep: View {
    @Bindable var app: AppModel
    let wantsWriting: Bool

    var body: some View {
        let models = app.setupModels(includingWriting: wantsWriting)
        let allReady = models.allSatisfy { app.setupStatus(of: $0) == .ready }
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(
                title: allReady ? "All set" : "Getting ready",
                subtitle: allReady
                    ? "Everything is downloaded and prepared. Try a dictation below."
                    : "You can close this window: the rest carries on in the background, and you'll get a notification when it's done."
            )
            Card(title: "Models") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(models) { model in
                        ProgressLine(model: model, status: app.setupStatus(of: model))
                    }
                }
            }
            TryItCard(app: app)
        }
    }
}

private struct ProgressLine: View {
    let model: SetupModel
    let status: SetupModelStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: model.name).font(.body.weight(.medium))
                Spacer()
                statusLabel
            }
            switch status {
            case .downloading(let fraction):
                ProgressView(value: fraction).tint(Color.pencil)
            case .preparing(let preparation?):
                TimelineView(.periodic(from: preparation.startedAt, by: 1)) { context in
                    ProgressView(value: min(context.date.timeIntervalSince(preparation.startedAt) / max(preparation.estimatedSeconds, 1), 0.95))
                        .tint(Color.pencil)
                }
            case .preparing(nil):
                ProgressView().progressViewStyle(.linear).tint(Color.pencil)
            default:
                EmptyView()
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .waiting:
            Text("Waiting its turn").font(.callout).foregroundStyle(.secondary)
        case .downloading(let fraction):
            Text("Downloading \(Int(fraction * 100))%").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        case .preparing(let preparation?):
            TimelineView(.periodic(from: preparation.startedAt, by: 1)) { context in
                Text(PreparationStatus.progressText(elapsed: context.date.timeIntervalSince(preparation.startedAt), estimate: preparation.estimatedSeconds))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .preparing(nil):
            Text("Preparing…").font(.callout).foregroundStyle(.secondary)
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).lineLimit(2)
        }
    }
}
