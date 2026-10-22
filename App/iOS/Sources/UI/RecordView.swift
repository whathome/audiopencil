import APCore
import APModels
import APTranscription
import SwiftUI

/// The recorder: talk, watch the words arrive, pause if you need to, stop and pick a style.
struct RecordView: View {
    let app: PhoneModel
    @State private var capture: PhoneCapture?

    private var recorder: PhoneRecorder { app.recorder }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusLine
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                transcript
                VStack(spacing: 18) {
                    meetingRow
                    clock
                    controls
                }
                .padding(.bottom, 28)
            }
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    LanguageMenu(app: app)
                }
            }
            .sheet(item: $capture, onDismiss: { recorder.clear() }) { capture in
                StyleSheet(app: app, capture: capture)
                    .presentationDetents([.medium, .large])
                    .tint(Color.pencil)
            }
        }
    }

    // MARK: Parts

    @ViewBuilder
    private var statusLine: some View {
        if let reason = recorder.pauseReason, recorder.phase == .paused {
            StatusRow(symbol: "pause.circle.fill", text: reason, tint: .orange)
        } else if app.notes.copied {
            StatusRow(symbol: "doc.on.clipboard", text: String(localized: "Copied to the clipboard"), tint: Color.pencil)
        } else if let processing = app.notes.processing {
            StatusRow(symbol: nil, text: processing)
        } else if let error = recorder.lastError, !recorder.isActive {
            StatusRow(symbol: "exclamationmark.triangle.fill", text: error, tint: .orange)
        } else {
            ModelStatusRow(app: app)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if recorder.liveText.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(recorder.liveText)
                            .textSelection(.enabled)
                    }
                }
                .font(.system(.title3, design: .serif))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .id("end")
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: recorder.liveText) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
    }

    private var placeholder: LocalizedStringResource {
        switch recorder.phase {
        case .idle: "Tap the button and talk. It's transcribed on this iPhone as you go, then written up as a note."
        case .starting: "Starting the microphone…"
        case .recording: "Listening…"
        case .paused: "Paused."
        case .finishing: "Finishing the transcript…"
        }
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            Text(PreparationStatus.clock(recorder.elapsed(at: context.date)))
                .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(recorder.phase == .paused ? .secondary : .primary)
                .contentTransition(.numericText())
        }
        .opacity(recorder.isActive ? 1 : 0.35)
        .accessibilityLabel(Text("Recorded time"))
    }

    /// Meeting mode, chosen before or during a recording: the note labels who said what. Off again after
    /// each recording, since most are one person talking.
    private var meetingRow: some View {
        HStack(spacing: 8) {
            Button {
                recorder.meeting.toggle()
            } label: {
                Label("Meeting", systemImage: "person.2")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(recorder.meeting ? Color.white : Color.primary)
                    .background(Capsule().fill(recorder.meeting ? Color.pencil : Color(.secondarySystemFill)))
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(recorder.meeting ? "On" : "Off"))
            .accessibilityHint(Text("Labels who said what in the note."))
            if recorder.meeting {
                Menu {
                    Picker("Speakers", selection: Binding(get: { recorder.speakerCount }, set: { recorder.speakerCount = $0 })) {
                        Text("Work it out").tag(Int?.none)
                        ForEach(2...6, id: \.self) { Text("\($0) people").tag(Int?.some($0)) }
                    }
                } label: {
                    Text(recorder.speakerCount.map { "\($0) people" as LocalizedStringResource } ?? "People: auto")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color(.secondarySystemFill)))
                }
                .accessibilityLabel(Text("Number of speakers"))
            }
            // Only offered when the vault has Obsidian's Daily notes on (Settings explains otherwise).
            if app.sync.dailyNotes == .on {
                let on = recorder.linksDailyNote
                Button {
                    recorder.dailyNoteOverride = !on
                } label: {
                    Label("Daily note", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(Capsule().fill(on ? Color.pencil : Color(.secondarySystemFill)))
                }
                .buttonStyle(.plain)
                .accessibilityValue(Text(on ? "On" : "Off"))
                .accessibilityHint(Text("Links the note in today's daily note."))
            }
        }
        .disabled(recorder.phase == .finishing)
        .animation(.snappy, value: recorder.meeting)
    }

    private var controls: some View {
        HStack(spacing: 36) {
            // Discard, on the left: only while there's something to throw away.
            CircleButton(symbol: "xmark", label: "Discard recording", size: 56, prominent: false) {
                recorder.cancel()
            }
            .opacity(recorder.phase == .recording || recorder.phase == .paused ? 1 : 0)
            .disabled(!(recorder.phase == .recording || recorder.phase == .paused))

            mainButton

            CircleButton(
                symbol: recorder.phase == .paused ? "play.fill" : "pause.fill",
                label: recorder.phase == .paused ? "Resume" : "Pause",
                size: 56,
                prominent: false
            ) {
                recorder.phase == .paused ? recorder.resume() : recorder.pause()
            }
            .opacity(recorder.phase == .recording || recorder.phase == .paused ? 1 : 0)
            .disabled(!(recorder.phase == .recording || recorder.phase == .paused))
        }
    }

    @ViewBuilder
    private var mainButton: some View {
        switch recorder.phase {
        case .idle:
            CircleButton(symbol: "mic.fill", label: "Record", size: 88, prominent: true) {
                Task { await recorder.start() }
            }
        case .starting, .finishing:
            ProgressView()
                .controlSize(.large)
                .frame(width: 88, height: 88)
        case .recording, .paused:
            CircleButton(symbol: "stop.fill", label: "Stop and make a note", size: 88, prominent: true) {
                Task { capture = await recorder.stop() }
            }
        }
    }
}

/// A round control: the big amber one records and stops; the small ones pause and discard.
struct CircleButton: View {
    let symbol: String
    let label: LocalizedStringResource
    let size: CGFloat
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .frame(width: size, height: size)
                .background(Circle().fill(prominent ? Color.pencil : Color(.secondarySystemFill)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: symbol)
        .accessibilityLabel(Text(label))
    }
}

struct StatusRow: View {
    let symbol: String?
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(tint)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(verbatim: text).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

/// The speech model's state, when it's anything but ready.
struct ModelStatusRow: View {
    let app: PhoneModel

    var body: some View {
        switch app.modelState {
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 6) {
                Text("Downloading Whisper \(app.speechModelName): \(Int(fraction * 100))%")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                ProgressView(value: fraction).tint(Color.pencil)
            }
        case .loading:
            if let preparation = app.preparation {
                PreparationStatus(title: String(localized: "Preparing Whisper \(app.speechModelName) for this iPhone"), preparation: preparation)
            } else {
                StatusRow(symbol: nil, text: String(localized: "Loading Whisper \(app.speechModelName)…"))
            }
        case .failed(let message):
            StatusRow(symbol: "exclamationmark.triangle.fill", text: message, tint: .orange)
        case .idle, .ready:
            EmptyView()
        }
    }
}

/// The language this recording is in; changing it mid-recording transcribes what's been said again.
struct LanguageMenu: View {
    let app: PhoneModel

    var body: some View {
        let current = app.recorder.isActive ? app.recorder.language : app.currentLanguage
        Menu {
            ForEach(app.offeredLanguages) { language in
                Button {
                    if app.recorder.isActive { app.recorder.select(language) } else { app.useLanguage(language) }
                } label: {
                    if language == current { Label(language.name(), systemImage: "checkmark") } else { Text(language.name()) }
                }
            }
        } label: {
            Text(current.badge)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.pencil.opacity(0.18)))
        }
        .accessibilityLabel(Text("Language: \(current.name())"))
        .disabled(app.offeredLanguages.count < 2 || app.recorder.phase == .finishing)
    }
}

/// After stopping: which style the note is written in. Starts on the last one used.
struct StyleSheet: View {
    let app: PhoneModel
    let capture: PhoneCapture
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String = ""

    var body: some View {
        NavigationStack {
            List(app.enabledStyles) { style in
                Button {
                    selection = style.id
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: style.displayName).foregroundStyle(.primary)
                            Text(verbatim: style.displayDescription).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        if selection == style.id { Image(systemName: "checkmark").foregroundStyle(Color.pencil) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain) // rows read as text, not as amber buttons
            }
            .navigationTitle("Write it as")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    if let style = app.enabledStyles.first(where: { $0.id == selection }), !style.isRaw, !app.writingModelDownloaded {
                        Text("The writing model isn't on this iPhone yet, so the note keeps the transcript as spoken.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    Button {
                        guard let style = chooseStyle() else { return }
                        app.notes.make(capture, style: style)
                        dismiss()
                    } label: {
                        Text("Make Note").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    // Same writing, but only onto the clipboard: no note is filed.
                    Button {
                        guard let style = chooseStyle() else { return }
                        app.notes.copy(capture, style: style)
                        dismiss()
                    } label: {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityHint(Text("Writes it in this style and copies it, without filing a note."))
                }
                .padding()
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) { dismiss() }
                }
            }
        }
        .onAppear { selection = app.lastStyle.id }
        .interactiveDismissDisabled()
    }

    /// The selected style, remembered as the last one used.
    private func chooseStyle() -> Style? {
        guard let style = app.enabledStyles.first(where: { $0.id == selection }) else { return nil }
        app.lastStyleID = style.id
        return style
    }
}
