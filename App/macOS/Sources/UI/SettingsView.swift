import APAudio
import APCore
import APModels
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, models, permissions
    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .models: "Models"
        case .permissions: "Permissions"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .models: "cpu"
        case .permissions: "checkmark.shield"
        }
    }
}

/// Settings in three tabs: General, Models, Permissions (which used to be the Setup page).
/// A page in the main window (segmented tabs under the title) or the ⌘, window (tab bar).
struct SettingsView: View {
    @Bindable var app: AppModel
    /// Shown as a page in the main window rather than the ⌘, Settings window.
    var embedded = false

    var body: some View {
        if embedded {
            content(app.settingsTab)
        } else {
            TabView(selection: $app.settingsTab) {
                ForEach(SettingsTab.allCases) { tab in
                    content(tab)
                        .tabItem { Label(tab.title, systemImage: tab.symbol) }
                        .tag(tab)
                }
            }
            .frame(width: 560, height: 660)
        }
    }

    @ViewBuilder
    private func content(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettings(app: app, embedded: embedded)
        case .models: ModelSettings(app: app, embedded: embedded)
        case .permissions: SetupView(app: app, showsHeader: false, settingsHeader: embedded)
        }
    }
}

/// Page title and tab switcher, placed in each tab's first section header so it lines up with the form.
struct SettingsHeader: View {
    @Bindable var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "Settings", subtitle: "Hotkey and sounds, the models on this Mac, and permissions.")
            HStack(spacing: 8) {
                Picker("", selection: $app.settingsTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 380)
                if app.needsSetup {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        .help("Permissions need attention")
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        // Section headers sit inset to the form's rows; pull the page title back to the 24 pt edge
        // the other pages' titles use.
        .padding(.leading, -10)
    }
}

extension View {
    /// Grouped forms centre themselves in the space they get. As a page in the main window, pin the form
    /// to the same left edge and width as the other pages, so titles line up when switching pages.
    func pageAligned(_ enabled: Bool) -> some View {
        modifier(PageAlignedForm(enabled: enabled))
    }
}

private struct PageAlignedForm: ViewModifier {
    let enabled: Bool
    /// A grouped form caps its sections at about 600 pt and centres them in the space it gets. Give it just
    /// over that, so the sections (and the title in the first header) start at the other pages' 24 pt edge.
    static let maxWidth: CGFloat = 620

    func body(content: Content) -> some View {
        if enabled {
            GeometryReader { geometry in
                content
                    .contentMargins(.leading, 4, for: .scrollContent)
                    .contentMargins(.trailing, max(4, geometry.size.width - Self.maxWidth), for: .scrollContent)
            }
        } else {
            content
        }
    }
}

/// Explanatory text under a form section: small, secondary and left-aligned, so it reads as a note
/// on the rows above rather than another setting.
private struct FormFooter: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A section title, preceded by the Settings header when shown as a page.
private struct FirstSectionHeader: View {
    let app: AppModel
    let embedded: Bool
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if embedded { SettingsHeader(app: app) }
            Text(title).font(.headline)
        }
    }
}

private struct GeneralSettings: View {
    @Bindable var app: AppModel
    var embedded = false

    var body: some View {
        Form {
            Section {
                Picker("Stop with", selection: $app.settings.stopGesture) {
                    ForEach(StopGesture.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle(isOn: $app.settings.holdFnForRaw) {
                    Text("Hold Fn for a raw transcript")
                    Text("Press and hold, talk, release to paste. Pressing another key while holding cancels, so Fn still works as a modifier.")
                }
                Toggle("Return also stops", isOn: $app.settings.returnStops)
                Toggle("⌃⌥Space starts and stops (for keyboards without Fn)", isOn: $app.settings.fallbackShortcutEnabled)
                LabeledContent("Double-tap speed") {
                    HStack {
                        Slider(value: $app.settings.doubleTapWindow, in: 0.25...0.7, step: 0.05)
                        Text("\(Int(app.settings.doubleTapWindow * 1000)) ms")
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                Toggle(isOn: $app.settings.warmMicOnFirstTap) {
                    Text("Start the mic on the first Fn tap")
                    Text("Recording starts instantly on the second tap. The mic indicator flashes briefly on a lone Fn tap.")
                }
            } header: {
                FirstSectionHeader(app: app, embedded: embedded, title: "Dictation hotkey")
            }


            Section("Sounds") {
                HStack {
                    Picker("Start and stop sounds", selection: $app.settings.cueTheme) {
                        ForEach(CueTheme.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }
                    Button {
                        app.dictation.previewSounds()
                    } label: {
                        Label("Play", systemImage: "speaker.wave.2")
                    }
                    .disabled(app.settings.cueTheme == CueTheme.none.rawValue)
                }
                LabeledContent("Volume") {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $app.settings.cueVolume, in: 0.05...1) { editing in
                            if !editing { app.dictation.previewSounds() }
                        }
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                }
                .disabled(app.settings.cueTheme == CueTheme.none.rawValue)
            }
            .onChange(of: app.settings.cueTheme) { app.dictation.previewSounds() }

            DictationLanguagesSection(app: app)

            MicrophonePriorityList(app: app)

            VocabularySection(app: app)

            Section {
                LabeledContent {
                    HStack(spacing: 6) {
                        Text("\(Int(app.settings.longFormThreshold / 60)) min").monospacedDigit()
                        Stepper("", value: $app.settings.longFormThreshold, in: 60...3_600, step: 60).labelsHidden()
                    }
                } label: {
                    Text("Make a note instead of pasting after")
                    Text("Longer recordings are kept with their audio and filed in the vault for review.")
                }
                Toggle(isOn: $app.settings.saveQuickDictations) {
                    Text("Save quick dictations as notes too")
                    Text("They still paste as usual; a copy is filed in the vault.")
                }
                Toggle(isOn: $app.expireRegularAudio) {
                    Text("Remove a recording's audio after a year")
                    Text("The note stays. Notes you move to Archive on the board keep their audio. Removed files go to the trash.")
                }
            } header: {
                Text("Notes")
            } footer: {
                FormFooter("Notes go to each style's folder (set on the Styles page), or \(NoteMaker.defaultFolder.dropFirst()). Audio goes to \(NoteMaker.recordingsFolder.dropFirst()).")
            }

            Section("App") {
                Toggle(isOn: $app.settings.menuBarMode) {
                    Text("Menu bar only")
                    Text("Hide the Dock icon and show Audio Pencil in the menu bar.")
                }
                Toggle("Launch at login", isOn: Binding(get: { app.launchAtLogin }, set: { app.setLaunchAtLogin($0) }))
                if app.launchAtLoginNeedsApproval {
                    Text("Approve Audio Pencil in System Settings › General › Login Items.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .pageAligned(embedded)
    }
}

/// Languages offered in the recording pill, which one new apps start in, and whether styles work in each.
private struct DictationLanguagesSection: View {
    @Bindable var app: AppModel

    var body: some View {
        Section {
            Picker(selection: Binding(
                get: { app.languageMemory.language(forApp: nil) },
                set: { app.chooseDefaultLanguage($0) }
            )) {
                ForEach(app.offeredLanguages) { Text($0.name()).tag($0) }
            } label: {
                Text("Start new apps in")
                Text("Each app starts in the language you last spoke there.")
            }
            ForEach(app.offeredLanguages) { language in
                HStack {
                    Text(language.name())
                    Text(language.badge).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if !app.canStyle(in: language) {
                        Text("Raw only with \(app.writingModelOption?.name ?? "this writing model")")
                            .font(.caption).foregroundStyle(.secondary)
                            .help("Styles need a writing model that writes this language. Raw transcripts still work.")
                    }
                    Button {
                        remove(language)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(app.offeredLanguages.count == 1)
                    .accessibilityLabel("Remove \(language.name())")
                }
            }
            if let fraction = app.multilingualDownload {
                LabeledContent("Downloading the multilingual model") {
                    ProgressView(value: fraction).frame(width: 160)
                }
            } else if app.multilingualPreparing {
                LabeledContent {
                    ProgressView().controlSize(.small)
                } label: {
                    Text("Preparing the multilingual model for this Mac")
                    Text("One time only, up to 15 minutes. Dictation waits until it's done.")
                }
            }
            Picker("Add a language", selection: Binding<String>(get: { "" }, set: { add($0) })) {
                Text("Choose…").tag("")
                ForEach(SpokenLanguage.all().filter { !app.offeredLanguages.contains($0) }) { Text($0.name()).tag($0.code) }
            }
        } header: {
            Text("Dictation languages")
        } footer: {
            FormFooter("One language per recording. Switch it from the language badge on the recording indicator. English uses the English model; other languages use the multilingual one (Settings › Models).")
        }
    }

    private func add(_ code: String) {
        guard !code.isEmpty else { return }
        app.settings.dictationLanguages = app.offeredLanguages.map(\.code) + [code]
    }

    private func remove(_ language: SpokenLanguage) {
        app.settings.dictationLanguages = app.offeredLanguages.map(\.code).filter { $0 != language.code }
        if app.languageMemory.language(forApp: nil) == language, let first = app.settings.offeredLanguages().first {
            app.chooseDefaultLanguage(first)
        }
    }
}

/// One list for every language, plus a list per language; a recording uses both.
private struct VocabularySection: View {
    @Bindable var app: AppModel
    /// "" edits the list for all languages; otherwise a Whisper code.
    @State private var list = ""
    @State private var text = ""

    var body: some View {
        Section {
            if app.isMultilingual {
                Picker("List", selection: $list) {
                    Text("All languages").tag("")
                    ForEach(app.offeredLanguages) { Text($0.name()).tag($0.code) }
                }
            }
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 70)
                .onChange(of: text) { _, text in save(text) }
        } header: {
            Text("Custom vocabulary")
        } footer: {
            FormFooter(list.isEmpty
                ? "One name, place or term per line, used in every language. Whisper gets them as spelling hints."
                : "Used only when dictating in \(SpokenLanguage(code: list).name()), on top of the list for all languages.")
        }
        .onAppear { load() }
        .onChange(of: list) { load() }
    }

    private func load() {
        text = (list.isEmpty ? app.settings.customVocabulary : app.settings.languageVocabulary[list] ?? []).joined(separator: "\n")
    }

    private func save(_ text: String) {
        let words = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if list.isEmpty {
            if words != app.settings.customVocabulary { app.settings.customVocabulary = words }
        } else if words != app.settings.languageVocabulary[list] ?? [] {
            app.settings.languageVocabulary[list] = words.isEmpty ? nil : words
        }
    }
}

private struct ModelSettings: View {
    @Bindable var app: AppModel
    var embedded = false

    var body: some View {
        Form {
            Section {
                Picker("Writing model", selection: $app.settings.writingModel) {
                    ForEach(WritingModelOption.catalogue) { option in
                        Text("\(option.name) – \(option.note)").tag(option.id)
                    }
                    if WritingModelOption.option(for: app.settings.writingModel) == nil {
                        Text(app.settings.writingModel.replacingOccurrences(of: "mlx-community/", with: "") + " – from discovery").tag(app.settings.writingModel)
                    }
                }
                .disabled(app.dictation.isActive)
                LabeledContent("Status") {
                    switch app.writingModelState {
                    case .downloading(let fraction): ProgressView(value: fraction).frame(width: 160)
                    case .failed(let message): Text(message).foregroundStyle(.red)
                    default:
                        if app.writingModelDownloaded {
                            Text("Downloaded").foregroundStyle(.secondary)
                        } else {
                            Button("Download (\(String(format: "%.1f", app.writingModelOption?.approximateDownloadGB ?? 2)) GB)") { app.downloadWritingModel() }
                        }
                    }
                }
                Toggle(isOn: $app.settings.pickStyleAfterStop) {
                    Text("Show a style picker after stopping")
                    Text("The style for this app is preselected and picked automatically unless you press a number.")
                }
                if app.settings.pickStyleAfterStop {
                    LabeledContent("Pick automatically after") {
                        HStack {
                            Slider(value: $app.settings.pickerAutoConfirm, in: 0.5...3, step: 0.25)
                            Text(String(format: "%.2g s", app.settings.pickerAutoConfirm)).monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            } header: {
                FirstSectionHeader(app: app, embedded: embedded, title: "Styles")
            } footer: {
                FormFooter("The writing model runs on this Mac. On 8 GB it swaps with the transcription model, so a styled dictation takes a few seconds longer than raw.")
            }

            Section("Transcription") {
                Picker("English", selection: $app.settings.transcriptionModel) {
                    ForEach(TranscriptionModelOption.catalogue) { option in
                        Text("\(option.name) – \(option.note)").tag(option.id)
                    }
                    if TranscriptionModelOption.option(for: app.settings.transcriptionModel) == nil {
                        Text(app.settings.transcriptionModel + " – from discovery").tag(app.settings.transcriptionModel)
                    }
                }
                .disabled(app.dictation.isActive)
                Picker("Other languages", selection: $app.settings.multilingualTranscriptionModel) {
                    ForEach(TranscriptionModelOption.multilingualCatalogue) { option in
                        Text("\(option.name) – \(option.note)").tag(option.id)
                    }
                    if TranscriptionModelOption.option(for: app.settings.multilingualTranscriptionModel) == nil {
                        Text(app.settings.multilingualTranscriptionModel + " – from discovery").tag(app.settings.multilingualTranscriptionModel)
                    }
                }
                .disabled(app.dictation.isActive)
                Toggle("Show live transcript above the indicator", isOn: $app.settings.showLiveText)
            }

            ModelSuggestionsSection(advisor: app.advisor)
        }
        .formStyle(.grouped)
        .pageAligned(embedded)
    }
}

/// Ordered list of preferred microphones; the first connected one is used.
private struct MicrophonePriorityList: View {
    @Bindable var app: AppModel

    var body: some View {
        Section {
            let preferences = app.settings.preferredMicrophones
            if preferences.isEmpty {
                Text("No preferences: using the system default input.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(preferences.enumerated()), id: \.element.uid) { index, preference in
                let connected = app.microphones.first { $0.id == preference.uid }
                HStack {
                    Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                    Image(systemName: icon(for: connected?.transport))
                        .frame(width: 18)
                    Text(preference.name)
                    if connected == nil {
                        Text("not connected").font(.caption).foregroundStyle(.secondary)
                    } else if app.currentMicrophone?.id == preference.uid {
                        Text("in use").font(.caption).foregroundStyle(.green)
                    }
                    Spacer()
                    Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(index == 0)
                        .accessibilityLabel("Move up")
                    Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(index == preferences.count - 1)
                        .accessibilityLabel("Move down")
                    Button { app.settings.preferredMicrophones.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        .accessibilityLabel("Remove from list")
                }
                .buttonStyle(.borderless)
            }
            let addable = app.microphones.filter { mic in !preferences.contains { $0.uid == mic.id } }
            Menu("Add Microphone") {
                ForEach(addable) { mic in
                    Button(mic.name) {
                        app.settings.preferredMicrophones.append(MicrophonePreference(uid: mic.id, name: mic.name))
                    }
                }
            }
            .disabled(addable.isEmpty)
            .fixedSize()
        } header: {
            Text("Microphones")
        } footer: {
            FormFooter("Uses the first connected microphone in this list, otherwise the system default. Now: \(app.currentMicrophoneName).")
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard app.settings.preferredMicrophones.indices.contains(target) else { return }
        app.settings.preferredMicrophones.swapAt(index, target)
    }

    private func icon(for transport: Microphone.Transport?) -> String {
        switch transport {
        case .builtIn: "laptopcomputer"
        case .bluetooth: "airpodspro"
        case .usb: "cable.connector"
        case .other: "mic"
        case nil: "mic.slash"
        }
    }
}

/// Discovery results: what fits this machine, with Try / Switch / Dismiss.
private struct ModelSuggestionsSection: View {
    let advisor: ModelAdvisor

    var body: some View {
        Section {
            LabeledContent("This Mac", value: advisor.machine.summary)
            LabeledContent("Room for models") {
                Text("writing up to \(Self.bytes(advisor.machine.writingModelBudget)), transcription up to \(Self.bytes(advisor.machine.transcriptionModelBudget))")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(advisor.lastChecked.map { "Last checked \($0.formatted(.relative(presentation: .named)))" } ?? "Not checked yet")
                    .foregroundStyle(.secondary)
                Spacer()
                if advisor.checking { ProgressView().controlSize(.small) }
                Button("Check now") { Task { await advisor.check() } }.disabled(advisor.checking)
            }
            if let error = advisor.checkError {
                Text(error).foregroundStyle(.orange).font(.callout)
            }
            ForEach(advisor.suggestions) { suggestion in
                SuggestionRow(advisor: advisor, suggestion: suggestion)
            }
            if advisor.suggestions.isEmpty, advisor.lastChecked != nil, !advisor.checking {
                Text("Nothing better that fits right now.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Model suggestions")
        } footer: {
            FormFooter("Audio Pencil checks Hugging Face weekly for transcription and writing models that fit this machine. Try one to compare it with your current model on this Mac; nothing changes until you choose Switch.")
        }
    }

    static func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory) }
}

private struct SuggestionRow: View {
    let advisor: ModelAdvisor
    let suggestion: ModelSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: suggestion.kind == .writing ? "pencil.and.scribble" : "waveform")
                    .foregroundStyle(Color.pencil)
                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.name).font(.headline)
                    Text("\(suggestion.kind == .writing ? "Writing" : "Transcription") · \(suggestion.sizeDescription) · \(suggestion.reason)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                switch advisor.trials[suggestion.id] {
                case .downloading(let fraction):
                    ProgressView(value: fraction).frame(width: 90)
                case .testing:
                    ProgressView().controlSize(.small)
                case .done:
                    Button("Switch") { advisor.adopt(suggestion) }.buttonStyle(.borderedProminent)
                default:
                    Button("Try") { advisor.tryOut(suggestion) }
                }
                Button { advisor.dismiss(suggestion) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.borderless)
                    .help("Don't suggest this again")
                    .accessibilityLabel("Don't suggest this again")
            }
            switch advisor.trials[suggestion.id] {
            case .testing(let status):
                Text(status).font(.caption).foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.orange)
            case .done(let lines):
                ForEach(lines) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.label).font(.caption.weight(.semibold))
                        HStack(alignment: .top, spacing: 12) {
                            result("This model", line.candidate, line.candidateSeconds, line.candidateWER)
                            result("Current", line.current, line.currentSeconds, line.currentWER)
                        }
                    }
                }
            default:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
    }

    private func result(_ title: String, _ text: String, _ seconds: Double, _ wer: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title).font(.caption.weight(.semibold))
                Text(String(format: "%.1f s", seconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if let wer {
                    Text("\(Int((wer * 100).rounded()))% word errors").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(text).font(.caption).textSelection(.enabled).lineLimit(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background.secondary))
    }
}
