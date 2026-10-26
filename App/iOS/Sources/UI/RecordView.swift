import APCore
import APModels
import APTranscription
import SwiftUI

/// The recorder: talk, watch the words arrive, pause if you need to, stop and pick a style.
struct RecordView: View {
    let app: PhoneModel
    @State private var capture: PhoneCapture?
    @State private var confirmingDiscard = false
    /// The clock follows the text size.
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 44

    /// Recordings longer than this ask before they're thrown away: a mis-tap shouldn't cost a walk.
    static let confirmDiscardAfter: TimeInterval = 30

    private var recorder: PhoneRecorder { app.recorder }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusLine
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                transcript
                VStack(spacing: 18) {
                    clock
                    controls
                }
                .padding(.bottom, 28)
            }
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
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
        if app.meetings.ownsCapture {
            StatusRow(symbol: "person.2", text: String(localized: "A meeting is recording or paused. Open Meetings for its controls."))
        } else if app.meetings.isProcessing {
            StatusRow(symbol: nil, text: app.meetings.progress)
        } else if let reason = recorder.pauseReason, recorder.phase == .paused {
            StatusRow(symbol: "pause.circle.fill", text: reason, tint: .orange)
        } else if let message = app.notes.justFinished {
            StatusRow(symbol: "checkmark.circle.fill", text: message, tint: Color.pencil)
        } else if recorder.isActive, !app.notes.queue.isEmpty {
            // Writing stops while recording (one model at a time); say so rather than let it vanish.
            StatusRow(symbol: "hourglass", text: String(localized: "\(app.notes.queue.count) waiting to be written: carries on when you stop"))
        } else if app.notes.processing != nil {
            WritingProgressRow(notes: app.notes)
        } else if !app.notes.queue.isEmpty {
            // Waiting with nothing running: say so here, where the app opens, and offer to start.
            HStack(spacing: 8) {
                Image(systemName: "tray.full").foregroundStyle(Color.pencil)
                Text("\(app.notes.queue.count) waiting to be written").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Write Now") { app.notes.processQueue() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
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
        case .idle: "Tap the button and talk. It's transcribed on this device as you go, then written up as a note or copied."
        case .starting: "Starting the microphone…"
        case .recording: "Listening…"
        case .paused: "Paused."
        case .finishing: "Finishing the transcript…"
        }
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            Text(PreparationStatus.clock(recorder.elapsed(at: context.date)))
                .font(.system(size: clockSize, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(recorder.phase == .paused ? .secondary : .primary)
                .contentTransition(.numericText())
        }
        .opacity(recorder.isActive ? 1 : 0.35)
        .accessibilityLabel(Text("Recorded time"))
    }

    private var controls: some View {
        HStack(spacing: 36) {
            // Discard, on the left: only while there's something to throw away.
            CircleButton(symbol: "xmark", label: "Discard recording", size: 56, prominent: false) {
                if recorder.elapsed() > Self.confirmDiscardAfter { confirmingDiscard = true } else { recorder.cancel() }
            }
            .opacity(recorder.phase == .recording || recorder.phase == .paused ? 1 : 0)
            .disabled(!(recorder.phase == .recording || recorder.phase == .paused))
            .confirmationDialog(
                Text("Discard this \(PreparationStatus.clock(recorder.elapsed())) recording?"),
                isPresented: $confirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard Recording", role: .destructive) { recorder.cancel() }
                Button("Keep Recording", role: .cancel) {}
            } message: {
                Text("It can't be brought back.")
            }

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
            .disabled(app.meetings.ownsCapture || app.meetings.isProcessing)
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

/// What note writing is doing: the step, a bar once its progress is known, and how long this recording has
/// been going, so a slow step reads as working rather than stuck.
struct WritingProgressRow: View {
    let notes: PhoneNotes

    var body: some View {
        if let step = notes.processing {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if notes.processingFraction == nil { ProgressView().controlSize(.small) }
                    Text(verbatim: step).font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let since = notes.processingSince {
                        TimelineView(.periodic(from: since, by: 1)) { context in
                            Text(PreparationStatus.clock(context.date.timeIntervalSince(since)))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                if let fraction = notes.processingFraction {
                    ProgressView(value: fraction)
                        .tint(Color.pencil)
                        .accessibilityValue(Text("\(Int(fraction * 100)) percent"))
                }
            }
            .accessibilityElement(children: .combine)
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
                PreparationStatus(title: String(localized: "Preparing Whisper \(app.speechModelName) for this device"), preparation: preparation)
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

/// After stopping: which style it's written in (starting on the last one used), and where it goes: a note
/// (linked in the daily note if wanted), the daily note itself, or the clipboard.
struct StyleSheet: View {
    let app: PhoneModel
    let capture: PhoneCapture
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String = ""
    @State private var confirmingDiscard = false
    /// For Make Note only; starts on the Settings choice.
    @State private var linksDailyNote = false

    private var dailyNotesOn: Bool { app.sync.dailyNotes == .on }

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
                        // Not a dead end: the download starts from here (and carries on after this sheet closes).
                        Text("The writing model isn't on this device yet, so this keeps the transcript as spoken. Get it to write in \(style.displayName).")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        WritingModelRow(app: app)
                            .font(.footnote)
                    }
                    Button {
                        var capture = capture
                        capture.dailyNote = dailyNotesOn && linksDailyNote
                        deliver(capture, as: .note)
                    } label: {
                        Label("Make Note", systemImage: "doc.text").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    if dailyNotesOn {
                        Toggle("Link it in today's daily note", isOn: $linksDailyNote)
                            .font(.subheadline)
                            .padding(.horizontal, 4)
                    }
                    // Same writing, somewhere other than a note of its own.
                    HStack(spacing: 8) {
                        if dailyNotesOn {
                            Button {
                                deliver(capture, as: .dailyNote)
                            } label: {
                                Label("Add to Daily Note", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                            }
                            .accessibilityHint(Text("Writes it in this style and adds it to today's daily note, without filing a note."))
                        }
                        Button {
                            deliver(capture, as: .copy)
                        } label: {
                            Label(dailyNotesOn ? "Copy" : "Copy to Clipboard", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                        }
                        .accessibilityHint(Text("Writes it in this style and copies it, without filing a note."))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding()
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .destructive) {
                        if capture.duration > RecordView.confirmDiscardAfter { confirmingDiscard = true } else { dismiss() }
                    } label: {
                        Text("Discard").foregroundStyle(.red)
                    }
                    .confirmationDialog(
                        Text("Discard this \(PreparationStatus.clock(capture.duration)) recording?"),
                        isPresented: $confirmingDiscard,
                        titleVisibility: .visible
                    ) {
                        Button("Discard Recording", role: .destructive) { dismiss() }
                        Button("Keep Recording", role: .cancel) {}
                    } message: {
                        Text("It can't be brought back.")
                    }
                }
            }
        }
        .onAppear {
            selection = app.lastStyle.id
            linksDailyNote = app.settings.dailyNoteLinks
        }
        .interactiveDismissDisabled()
    }

    /// Queues it in the selected style, which is remembered as the last one used.
    private func deliver(_ capture: PhoneCapture, as outcome: PhoneNotes.Outcome) {
        guard let style = app.enabledStyles.first(where: { $0.id == selection }) else { return }
        app.lastStyleID = style.id
        app.notes.enqueue(capture, style: style, outcome: outcome)
        dismiss()
    }
}
