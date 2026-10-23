import APAudio
import APCore
import APModels
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, dictation, notes, models, permissions
    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .general: "General"
        case .dictation: "Dictation"
        case .notes: "Notes"
        case .models: "Models"
        case .permissions: "Permissions"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .dictation: "mic"
        case .notes: "doc.text"
        case .models: "cpu"
        case .permissions: "checkmark.shield"
        }
    }
}

/// Focused settings categories, shared by the main page and the standalone Settings window.
/// A page in the main window or the ⌘, window, with the same category buttons in both.
struct SettingsView: View {
    @Bindable var app: AppModel
    /// Shown as a page in the main window rather than the ⌘, Settings window.
    var embedded = false

    var body: some View {
        if embedded {
            content(app.settingsTab)
        } else {
            VStack(spacing: 0) {
                SettingsCategoryControl(selection: $app.settingsTab, needsPermissions: app.needsSetup)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                Divider()
                content(app.settingsTab)
            }
            .frame(width: 640, height: 740)
        }
    }

    @ViewBuilder
    private func content(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettings(app: app, embedded: embedded)
        case .dictation: DictationSettingsView(app: app, embedded: embedded)
        case .notes: NoteSettings(app: app, embedded: embedded)
        case .models: ModelSettings(app: app, embedded: embedded)
        case .permissions: SetupView(app: app, showsHeader: false, settingsHeader: embedded)
        }
    }
}

/// Page title and categories, aligned with the first form section.
struct SettingsHeader: View {
    @Bindable var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "Settings", subtitle: "App behavior, dictation, notes, models and permissions.")
            SettingsCategoryControl(selection: $app.settingsTab, needsPermissions: app.needsSetup)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        // Section headers sit inset to the form's rows; pull the page title back to the 24 pt edge
        // the other pages' titles use.
        .padding(.leading, -10)
    }
}

private struct SettingsCategoryControl: View {
    @Binding var selection: SettingsTab
    let needsPermissions: Bool

    var body: some View {
        GeometryReader { geometry in
            let side = min(96, (geometry.size.width - 32) / CGFloat(SettingsTab.allCases.count))
            HStack(spacing: 8) {
                ForEach(SettingsTab.allCases) { tab in
                    let selected = selection == tab
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(selected ? Color.pencil : Color.secondary)
                                .accessibilityHidden(true)
                            Text(tab.title)
                                .font(.callout.weight(selected ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .padding(6)
                        .frame(width: side, height: side)
                        .background(selected ? Color.pencil.opacity(0.14) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selected ? Color.pencil : Color.secondary.opacity(0.25), lineWidth: selected ? 1.5 : 0.5)
                        }
                        .overlay(alignment: .topTrailing) {
                            if tab == .permissions, needsPermissions {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                                    .padding(6)
                                    .help("Permissions need attention")
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(tab.title))
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .accessibilityValue(tab == .permissions && needsPermissions ? Text("Permissions need attention") : Text(""))
                    .help(Text(tab.title))
                }
            }
        }
        .frame(height: 96)
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
    let text: LocalizedStringResource
    init(_ text: LocalizedStringResource) { self.text = text }

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
    let title: LocalizedStringResource

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
                LabeledContent {
                    Button("Run Setup Again…") { app.showSetup(hidingMainWindow: false) }
                } label: {
                    Text("Setup")
                    Text("Walks through the dictation key, permissions, languages, storage and models. Nothing is reset.")
                }
            } header: {
                FirstSectionHeader(app: app, embedded: embedded, title: "App")
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
                        .accessibilityLabel(Text("Sound volume"))
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                }
                .disabled(app.settings.cueTheme == CueTheme.none.rawValue)
            }
            .onChange(of: app.settings.cueTheme) { app.dictation.previewSounds() }
        }
        .formStyle(.grouped)
        .pageAligned(embedded)
    }
}

private struct DictationSettingsView: View {
    @Bindable var app: AppModel
    var embedded = false
    @State private var showsHotkeyOptions = false

    private var clipboardDetail: LocalizedStringResource {
        if #available(macOS 15.4, *), NSPasteboard.general.accessBehavior == .alwaysDeny {
            return "macOS is set to deny Audio Pencil clipboard access (Privacy & Security › Paste from Other Apps), so dictations stay on the clipboard."
        }
        return app.settings.keepClipboard
            ? "Dictation pastes through the clipboard, then your clipboard goes back once the text is seen to arrive. If that can't be confirmed, the dictation stays on the clipboard so ⌘V pastes it. Passwords copied from a password manager aren't kept."
            : "Each dictation is left on the clipboard after pasting, replacing what was there."
    }

    var body: some View {
        Form {
            Section {
                let key = app.settings.gestureKey
                Picker(selection: $app.settings.gestureKey) {
                    ForEach(GestureKey.allCases, id: \.self) { Text(verbatim: $0.name).tag($0) }
                } label: {
                    Text("Key")
                    Text("Right ⌥ or Right ⌘ suit keyboards without a usable Fn key.")
                }
                Picker("Start with", selection: $app.settings.startGesture) {
                    ForEach(StartGesture.allCases, id: \.self) { Text(verbatim: $0.label(key)).tag($0) }
                }
                Picker(selection: Binding(get: { app.settings.effectiveStopGesture }, set: { app.settings.stopGesture = $0 })) {
                    ForEach(StopGesture.allCases, id: \.self) { Text(verbatim: $0.label(key)).tag($0) }
                } label: {
                    Text("Stop with")
                    if app.settings.startGesture == .singleTap {
                        Text("A tap starts, so a tap stops.")
                    }
                }
                .disabled(app.settings.startGesture == .singleTap)
                Toggle("Return also stops", isOn: $app.settings.returnStops)
                DisclosureGroup("Timing and shortcuts", isExpanded: $showsHotkeyOptions) {
                    LabeledContent {
                        HStack(spacing: 8) {
                            ShortcutRecorder(app: app)
                                .disabled(!app.settings.fallbackShortcutEnabled)
                            Toggle("", isOn: $app.settings.fallbackShortcutEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel(Text("Shortcut"))
                        }
                    } label: {
                        Text("Shortcut")
                        Text("Also starts and stops dictation. Click it to record a different one.")
                    }
                    if app.settings.startGesture == .doubleTap || app.settings.effectiveStopGesture == .doubleTapFn {
                        LabeledContent("Double-tap speed") {
                            HStack {
                                Slider(value: $app.settings.doubleTapWindow, in: 0.25...0.7, step: 0.05) {
                                    Text("Double-tap speed")
                                }
                                .labelsHidden()
                                .accessibilityValue(Text("\(Int((app.settings.doubleTapWindow * 1000).rounded())) milliseconds"))
                                Text("\(Int((app.settings.doubleTapWindow * 1000).rounded())) ms")
                                    .monospacedDigit()
                                    .frame(width: 70, alignment: .trailing)
                            }
                        }
                    }
                    if app.settings.startGesture == .doubleTap {
                        Toggle(isOn: $app.settings.warmMicOnFirstTap) {
                            Text("Start the mic on the first \(key.name) tap")
                            Text("Recording starts instantly on the second tap. The mic indicator flashes briefly on a lone \(key.name) tap.")
                        }
                    }
                }
            } header: {
                FirstSectionHeader(app: app, embedded: embedded, title: "Dictation hotkey")
            }

            Section("Push-to-talk") {
                Toggle(isOn: $app.settings.holdFnForRaw) {
                    Text("Hold \(app.settings.gestureKey.name) for a raw transcript")
                    Text("Press and hold, talk, release to paste. Pressing another key while holding cancels, so \(app.settings.gestureKey.name) still works as a modifier.")
                }
                if app.settings.holdFnForRaw {
                    LabeledContent {
                        HStack {
                            Slider(value: $app.settings.pushToTalkDelay, in: DictationSettings.pushToTalkDelayRange, step: 0.05) {
                                Text("Push-to-talk delay")
                            }
                            .labelsHidden()
                            .accessibilityValue(Text("\(Int((app.settings.pushToTalkDelay * 1000).rounded())) milliseconds"))
                            Text("\(Int((app.settings.pushToTalkDelay * 1000).rounded())) ms")
                                .monospacedDigit()
                                .frame(width: 70, alignment: .trailing)
                        }
                    } label: {
                        Text("Push-to-talk delay")
                        Text("Shorter starts sooner but makes accidental recordings easier. Default: 350 ms.")
                    }
                }
            }

            Section("After recording") {
                Toggle(isOn: $app.settings.pickStyleAfterStop) {
                    Text("Show a style picker after stopping")
                    Text("The style for this app is preselected and picked automatically unless you press a number.")
                }
                if app.settings.pickStyleAfterStop {
                    LabeledContent("Pick automatically after") {
                        HStack {
                            Slider(value: $app.settings.pickerAutoConfirm, in: 0.5...3, step: 0.25) {
                                Text("Style picker delay")
                            }
                            .labelsHidden()
                            Text(String(format: "%.2g s", app.settings.pickerAutoConfirm))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                Toggle(isOn: $app.settings.keepClipboard) {
                    Text("Keep what's on my clipboard")
                    Text(clipboardDetail)
                }
            }

            MicrophonePriorityList(app: app)

            Section("Recording indicator") {
                Toggle("Show live transcript above the indicator", isOn: $app.settings.showLiveText)
            }

            DictationLanguagesSection(app: app)

            VocabularySection(app: app)
        }
        .formStyle(.grouped)
        .pageAligned(embedded)
    }
}

private struct NoteSettings: View {
    @Bindable var app: AppModel
    var embedded = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: 6) {
                        Text("\(Int(app.settings.longFormThreshold / 60)) min").monospacedDigit()
                        Stepper("", value: $app.settings.longFormThreshold, in: 60...3_600, step: 60).labelsHidden()
                    }
                } label: {
                    Text("Make a note instead of pasting after")
                    Text("Longer recordings are kept with their audio and filed with your notes for review.")
                }
                Toggle(isOn: $app.settings.saveQuickDictations) {
                    Text("Save quick dictations as notes too")
                    Text("They still paste as usual; a copy is filed with your notes.")
                }
                Toggle(isOn: $app.expireRegularAudio) {
                    Text("Remove a recording's audio after a year")
                    Text("The note stays. Notes you move to Archive on the board keep their audio. Removed files go to the trash.")
                }
            } header: {
                FirstSectionHeader(app: app, embedded: embedded, title: "Saving and retention")
            } footer: {
                FormFooter("Notes go to each style's folder (set on the Styles page), or \(String(NoteMaker.defaultFolder.dropFirst())). Audio goes to \(String(NoteMaker.recordingsFolder.dropFirst())).")
            }

            DailyNoteSection(app: app)

            PushToTalkSection(app: app)

            TaskKeywordsSection(app: app)
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
            } else if let preparation = app.preparation {
                PreparationStatus(title: app.preparationTitle(preparation), preparation: preparation, blocking: app.isBlocking(preparation))
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

/// Linking new notes in Obsidian's daily note. Greyed out until the vault has Daily notes on.
private struct DailyNoteSection: View {
    @Bindable var app: AppModel

    private var available: Bool { app.sync.dailyNotes == .on }

    var body: some View {
        Section {
            Toggle(isOn: $app.settings.dailyNoteLinks) {
                Text("Link new notes in the daily note")
                Text("Each note is linked in the daily note for the day it was recorded, created if it isn't there yet. Change it for one recording in the recording indicator's menu.")
            }
            .disabled(!available)
            TextField("Under the heading", text: $app.settings.dailyNoteHeading, prompt: Text("At the end of the note"))
                .disabled(!available || !app.settings.dailyNoteLinks)
            Picker("Add it as", selection: $app.settings.dailyNoteEmbed) {
                Text("A link").tag(false)
                Text("The whole note, embedded").tag(true)
            }
            .disabled(!available || !app.settings.dailyNoteLinks)
        } header: {
            Text("Daily note")
        } footer: {
            switch app.sync.dailyNotes {
            case .on: FormFooter("A link reads \"- 14:32 [[Title]]\". Leave the heading blank to add at the end of the daily note.")
            case .off: FormFooter("Turn on Daily notes in Obsidian (Settings › Core plugins) first. Daily notes need your storage to be an Obsidian vault.")
            case .unknown: FormFooter("Connect your storage first; Audio Pencil checks whether Obsidian's Daily notes is on.")
            }
        }
    }
}

/// Push-to-talk only pastes; while holding the key, the pill can also send it to the daily note or a file.
private struct PushToTalkSection: View {
    @Bindable var app: AppModel

    var body: some View {
        Section {
            TextField("File", text: $app.settings.pushToTalkFile, prompt: Text(verbatim: "Inbox.md"))
            TextField("Under the heading", text: $app.settings.pushToTalkHeading, prompt: Text("At the end of the file"))
        } header: {
            Text("Push-to-talk filing")
        } footer: {
            FormFooter("Push-to-talk pastes, and that's all unless you choose otherwise: while holding the key, click the pill's \"Paste\" badge to also add the text to today's daily note or this file (in your storage, created if missing), as \"- 14:32 the text\". A task keyword gives a task line with no time.")
        }
    }
}

/// Phrases that turn a dictation into an Obsidian task.
private struct TaskKeywordsSection: View {
    @Bindable var app: AppModel
    @State private var text = ""

    var body: some View {
        Section {
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 60)
                .onChange(of: text) { _, text in
                    let phrases = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if phrases != app.taskKeywords { app.taskKeywords = phrases }
                }
        } header: {
            Text("Task keywords")
        } footer: {
            FormFooter("One phrase per line. A dictation that starts with one is pasted as an Obsidian task: \"New task: call the landlord by Friday\" becomes \"- [ ] Call the landlord by Friday 📅 date\", with due and start dates in the Tasks plugin's format. Shared with your other devices.")
        }
        .onAppear { text = app.taskKeywords.joined(separator: "\n") }
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
                ? "One name, place or term per line, used in every language. Whisper gets them as spelling hints." as LocalizedStringResource
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
                        Text("\(app.settings.writingModel.replacingOccurrences(of: "mlx-community/", with: "")) – from discovery").tag(app.settings.writingModel)
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
                        Text("\(app.settings.transcriptionModel) – from discovery").tag(app.settings.transcriptionModel)
                    }
                }
                .disabled(app.dictation.isActive || app.usesPhonon)
                Toggle(isOn: $app.phononTrial) {
                    Text("Try Phonon-2 for English")
                    if app.phononTrial, !app.usesPhonon {
                        Text("Whisper stays on while you have a custom vocabulary: Phonon-2 can't take one.")
                    } else {
                        Text("Fewer mistakes and faster than Whisper Small in tests. English only. A 370 MB download, then about 5 minutes preparing for this Mac the first time.")
                    }
                }
                .disabled(app.dictation.isActive)
                Picker("Other languages", selection: $app.settings.multilingualTranscriptionModel) {
                    ForEach(TranscriptionModelOption.multilingualCatalogue) { option in
                        Text("\(option.name) – \(option.note)").tag(option.id)
                    }
                    if TranscriptionModelOption.option(for: app.settings.multilingualTranscriptionModel) == nil {
                        Text("\(app.settings.multilingualTranscriptionModel) – from discovery").tag(app.settings.multilingualTranscriptionModel)
                    }
                }
                .disabled(app.dictation.isActive)
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
                Group {
                    if let checked = advisor.lastChecked {
                        Text("Last checked \(checked.formatted(.relative(presentation: .named)))")
                    } else {
                        Text("Not checked yet")
                    }
                }
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

    private func result(_ title: LocalizedStringResource, _ text: String, _ seconds: Double, _ wer: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title).font(.caption.weight(.semibold))
                Text("\(seconds.formatted(.number.precision(.fractionLength(1)))) s").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if let wer {
                    Text("\(Int((wer * 100).rounded()))% word errors").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(verbatim: text).font(.caption).textSelection(.enabled).lineLimit(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background.secondary))
    }
}
