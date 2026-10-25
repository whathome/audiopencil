import APAudio
import APCore
import AppKit
import AVFoundation
import SwiftUI

struct MeetingsPage: View {
    let app: AppModel
    @Bindable var meetings: MeetingController
    @State private var reviewSection = ReviewSection.summary
    @State private var discarding = false
    @State private var deleting: UUID?
    @State private var player = AVPlayer()
    @State private var playbackError: String?

    private enum ReviewSection: String, CaseIterable {
        case summary, actions, transcript
        var title: LocalizedStringResource {
            switch self {
            case .summary: "Summary"
            case .actions: "Actions"
            case .transcript: "Transcript"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Meetings", subtitle: "Be in the conversation. Keep the decisions, actions and words.")
                if let error = meetings.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if meetings.ownsCapture {
                    recording
                } else if let session = meetings.selected {
                    review(session)
                } else {
                    setup
                }
                if !meetings.ownsCapture { recent }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .onDisappear {
            meetings.endPreview()
            player.pause()
        }
        .onChange(of: meetings.selectedID) { _, _ in
            player.pause()
            player.replaceCurrentItem(with: nil)
            playbackError = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem, item === player.currentItem else { return }
            playbackError = item.error?.localizedDescription ?? String(localized: "The recording could not be played. Open the local files to inspect it.")
        }
        .confirmationDialog("Discard this meeting recording?", isPresented: $discarding) {
            Button("Discard Recording", role: .destructive) { Task { await meetings.stop(discard: true) } }
        } message: {
            Text("The recording will go to the Trash. This cannot be undone in Audio Pencil.")
        }
        .confirmationDialog("Delete the local meeting and its recordings?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Local Meeting", role: .destructive) {
                if let deleting { meetings.delete(deleting) }
                deleting = nil
            }
        } message: {
            Text("Local recovery files and review data go to the Trash. Any note already filed in your storage stays there; delete it there separately.")
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField("Meeting title (optional)", text: $meetings.title)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Meeting title")
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                GridRow {
                    Text("Meeting type")
                    Picker("Meeting type", selection: $meetings.kind) {
                        Text("In person").tag(MeetingSession.Kind.inPerson)
                        Text("Video call (preview)").tag(MeetingSession.Kind.videoCall)
                            .disabled(!CallAudioCapture.isAvailable)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                GridRow {
                    Text("Microphone")
                    Picker("Microphone", selection: $meetings.microphoneUID) {
                        Text("Preferred: \(app.microphoneShortName)").tag("")
                        ForEach(app.microphones) { microphone in
                            Text(verbatim: microphone.name).tag(microphone.id)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Input level")
                    HStack {
                        ProgressView(value: Double(meetings.microphoneLevel)).accessibilityLabel("Microphone level")
                        Button(meetings.previewing ? "Stop Test" : "Test Microphone") {
                            if meetings.previewing { meetings.endPreview() }
                            else { Task { await meetings.previewMicrophone() } }
                        }
                        .disabled(app.dictation.isActive || meetings.previewStarting)
                    }
                }
                if meetings.kind == .videoCall {
                    GridRow {
                        Text("Call audio")
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Call app", selection: $meetings.applicationID) {
                                Text("Choose a running app").tag(Int32?.none)
                                ForEach(meetings.applications) { application in
                                    Text(verbatim: application.name).tag(Optional(application.id))
                                }
                            }
                            .labelsHidden()
                            Button("Allow Call Audio / Refresh Apps") { Task { await meetings.refreshApplications() } }
                                .disabled(meetings.loadingApplications || !CallAudioCapture.isAvailable)
                            callAudioPreview
                        }
                        .task(id: app.dictation.isActive ? nil : meetings.applicationID) { meetings.previewCallAudio() }
                        .onDisappear { meetings.callPreview.stop() }
                    }
                }
                GridRow {
                    Text("Language")
                    Picker("Meeting language", selection: $meetings.language) {
                        ForEach(app.offeredLanguages, id: \.code) { language in
                            Text(verbatim: language.name()).tag(language)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Speakers")
                    Picker("Number of speakers", selection: $meetings.speakerHint) {
                        Text("Automatic").tag(Int?.none)
                        ForEach(2...6, id: \.self) { Text("\($0)").tag(Optional($0)) }
                    }
                    .labelsHidden()
                }
            }
            .padding(16)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))

            if !CallAudioCapture.isAvailable {
                Label("Video-call recording is not available in this build while app-audio capture is being verified.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if meetings.kind == .videoCall {
                Text("Preview: confirm both source meters respond before relying on this recording.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Echo cancellation reduces speaker audio leaking into your microphone. Headphones remain the most reliable option. Browser capture can include other tabs.", systemImage: "headphones")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Process after recording", isOn: $meetings.processAfterRecording)
                if app.sync.dailyNotes == .on {
                    Toggle("Link in today's daily note", isOn: $meetings.dailyNote)
                }
                Label(app.vault.settings.isConfigured
                      ? "Notes go to Audio Pencil/Notes in your connected storage."
                      : "Saved on this Mac until you set up storage.", systemImage: "externaldrive")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !app.speech.isDownloaded || !app.writing.isDownloaded {
                Label("A model is not downloaded. You can record now and process later after downloading models in Settings.", systemImage: "arrow.down.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            Text("Make sure everyone knows this meeting is being recorded. Audio Pencil does not notify participants.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Button("Start Meeting", systemImage: "record.circle") { Task { await meetings.start() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(startBlocker != nil)
                if let startBlocker {
                    Text(startBlocker)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onChange(of: meetings.microphoneUID) { _, _ in meetings.endPreview() }
    }

    private var startBlocker: LocalizedStringResource? {
        if meetings.isProcessing { return "Wait for meeting processing to finish." }
        if app.dictation.isActive { return "Finish dictation first." }
        if meetings.previewStarting { return "Wait for the microphone test to start." }
        if meetings.resolvedMicrophone == nil { return "Connect a microphone to start a meeting." }
        if meetings.kind == .videoCall {
            if !CallAudioCapture.isAvailable { return "Choose In person for microphone-only recording." }
            if meetings.applicationID == nil { return "Choose a call app to start a video meeting." }
        }
        return nil
    }

    private var callAudioPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            if meetings.applicationID != nil {
                ProgressView(value: Double(meetings.callPreview.level))
                    .accessibilityLabel("Selected app audio level")
                    .accessibilityValue(Text("\(Int(meetings.callPreview.level * 100)) percent"))
                if meetings.callPreview.isStarting {
                    ProgressView("Connecting to app audio…").controlSize(.small)
                } else if let error = meetings.callPreview.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                    Button("Retry Audio Preview") { meetings.previewCallAudio() }
                        .disabled(app.dictation.isActive || !CallAudioCapture.isAvailable)
                } else if meetings.callPreview.isMonitoring {
                    Label(meetings.callPreview.hasAudio ? "Audio detected from this app" : "Play audio in the selected app to check its level",
                          systemImage: meetings.callPreview.hasAudio ? "checkmark.circle" : "speaker.wave.2")
                        .foregroundStyle(.secondary)
                } else if app.dictation.isActive {
                    Text("Finish dictation to preview call audio.").foregroundStyle(.secondary)
                }
                Text("Live level preview only. Nothing is saved or replayed.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Select an app to preview its audio level.").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var recording: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let session = meetings.selected {
                Text(verbatim: session.title).font(.system(.title2, design: .serif).weight(.semibold))
                HStack(spacing: 12) {
                    Label(meetings.capture == .paused ? "Paused" : meetings.capture == .starting ? "Starting" : "Recording",
                          systemImage: meetings.capture == .paused ? "pause.circle" : "record.circle")
                        .foregroundStyle(meetings.capture == .paused ? Color.secondary : Color.pencil)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.clock(meetings.elapsed(at: context.date))).monospacedDigit()
                    }
                }
                sourceMeter(session.kind == .videoCall ? "You (echo reduced)" : "Microphone", name: session.microphoneName, value: meetings.microphoneLevel)
                if session.kind == .videoCall {
                    sourceMeter("Call audio", name: session.applicationName ?? "", value: meetings.callLevel)
                    Text("The call app may be quiet while someone is listening. Quiet input does not stop the recording.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Echo reduction takes a moment to adapt at the start and after pauses. Speaker leakage may remain while it settles.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if meetings.capture == .paused {
                    Picker("Resume microphone", selection: $meetings.microphoneUID) {
                        Text("Original microphone").tag("")
                        ForEach(app.microphones) { Text(verbatim: $0.name).tag($0.id) }
                    }
                    if session.kind == .videoCall, !session.callAudioEnded {
                        Button("Continue without call audio") { Task { await meetings.continueWithoutCallAudio() } }
                    }
                }
            } else {
                ProgressView("Starting the microphone…")
            }
            HStack {
                Button(meetings.capture == .paused ? "Resume" : "Pause", systemImage: meetings.capture == .paused ? "play" : "pause") {
                    Task { await meetings.togglePause() }
                }
                Button("Stop Meeting", systemImage: "stop.fill") { Task { await meetings.stop() } }
                    .buttonStyle(.borderedProminent)
            }
            .disabled(meetings.capture == .starting || meetings.capture == .stopping)
            Text("You can close this window. The floating indicator and menu bar keep the meeting controls available.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Discard recording…", role: .destructive) { discarding = true }
                .disabled(meetings.capture == .starting || meetings.capture == .stopping)
        }
    }

    private func sourceMeter(_ label: LocalizedStringResource, name: String, value: Float) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.headline)
                Text(verbatim: name).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(value))
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text("\(Int(value * 100)) percent"))
        }
    }

    private func review(_ session: MeetingSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("New Meeting", systemImage: "plus") { meetings.selectedID = nil }
                .buttonStyle(.link)
            TextField("Meeting title", text: Binding(get: { meetings.selected?.title ?? session.title }, set: { meetings.update(session.id, title: $0) }))
                .font(.system(.title2, design: .serif).weight(.semibold))
                .textFieldStyle(.plain)
                .disabled(meetings.processingID == session.id)
            if session.processingRequested {
                Label("Waiting to process after the current recording or job.", systemImage: "clock")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("\(session.recorded.formatted(date: .abbreviated, time: .shortened)) · \(Self.clock(session.duration)) · \(meetings.filingStatus(session))")
                .font(.callout).foregroundStyle(.secondary)
            if meetings.processingID == session.id {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(verbatim: meetings.progress)
                }
            } else if session.stage == .saved || session.stage == .failed {
                if let error = session.error { Text(verbatim: error).foregroundStyle(.orange).textSelection(.enabled) }
                HStack {
                    Button(session.turns.isEmpty ? "Process Saved Recording" : "Retry Summary") {
                        meetings.process(session.id, retrySummaryOnly: !session.turns.isEmpty)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(meetings.isProcessing || app.dictation.isActive)
                    if !session.turns.isEmpty {
                        Button("Retry Transcription") { meetings.process(session.id) }
                            .disabled(meetings.isProcessing || app.dictation.isActive)
                    }
                }
            }
            ForEach(Array(Set(session.warnings)).sorted(), id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            playback(session)
            if !session.turns.isEmpty {
                Picker("Meeting review", selection: $reviewSection) {
                    ForEach(ReviewSection.allCases, id: \.self) { section in Text(section.title).tag(section) }
                }
                .pickerStyle(.segmented)
                switch reviewSection {
                case .summary:
                    if session.summary.isEmpty {
                        Text("The transcript is saved. A summary will appear after processing.").foregroundStyle(.secondary)
                    } else {
                        MeetingProse(text: session.displayingSpeakerNames(in: session.summary))
                    }
                case .actions:
                    Text("Edit tasks, owners and dates as Markdown. Unknown owners and deadlines should stay unset.")
                        .font(.callout).foregroundStyle(.secondary)
                    TextEditor(text: Binding(get: { meetings.selected?.actions ?? session.actions }, set: { meetings.update(session.id, actions: $0) }))
                        .font(.body)
                        .frame(minHeight: 180)
                        .border(.separator)
                        .accessibilityLabel("Meeting action items")
                        .disabled(meetings.processingID == session.id)
                case .transcript:
                    speakerNames(session)
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(session.turns) { turn in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Button(Self.clock(turn.start)) { play(session, at: turn.start) }
                                        .buttonStyle(.link)
                                        .monospacedDigit()
                                        .accessibilityLabel(Text("Play from \(Self.clock(turn.start))"))
                                    Text(verbatim: session.speakerName(turn.speaker)).font(.headline)
                                }
                                Text(verbatim: turn.text.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .font(.system(.body, design: .serif))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack { reviewActions(session) }
                    VStack(alignment: .leading, spacing: 10) { reviewActions(session) }
                }
            }
            HStack {
                Button("Show Local Files") { NSWorkspace.shared.open(meetings.directory(for: session.id)) }
                if session.retention != .archive {
                    Button("Keep Audio Forever") { meetings.keepForever(session.id) }
                        .disabled(meetings.isProcessing || meetings.filing || session.audioExpired)
                } else {
                    Label("Kept forever", systemImage: "infinity").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Delete local meeting…", role: .destructive) { deleting = session.id }
                    .disabled(meetings.isProcessing || meetings.filing)
            }
            .font(.callout)
        }
    }

    @ViewBuilder private func reviewActions(_ session: MeetingSession) -> some View {
        Button(session.reviewed ? "Reviewed" : "Mark Reviewed", systemImage: session.reviewed ? "checkmark.circle.fill" : "checkmark.circle") {
            meetings.update(session.id, reviewed: true)
            Task { await meetings.file(session.id) }
        }
        .buttonStyle(.borderedProminent)
        .disabled(meetings.isProcessing || meetings.filing)
        Button("Update Filed Note") { Task { await meetings.file(session.id) } }
            .disabled(meetings.isProcessing || meetings.filing)
        Button("Copy Summary") { app.dictation.paster.copy(session.displayingSpeakerNames(in: session.body)) }
        if let path = session.notePath, let url = app.notes.openURL(for: path) {
            Link(app.vault.layout == .obsidian ? "Open in Obsidian" : "Open File", destination: url)
        }
    }

    private func speakerNames(_ session: MeetingSession) -> some View {
        DisclosureGroup("Speaker names") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(Set(session.turns.map(\.speaker)).sorted(), id: \.self) { id in
                    GridRow {
                        Text(verbatim: id == "you" ? String(localized: "You") : id).foregroundStyle(.secondary)
                        TextField("Name", text: Binding(
                            get: { meetings.selected?.speakerNames[id] ?? "" },
                            set: { meetings.update(session.id, speaker: id, name: $0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(Text("Name for \(session.speakerName(id))"))
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func playback(_ session: MeetingSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if FileManager.default.fileExists(atPath: meetings.playbackURL(for: session.id).path) {
                HStack {
                    Button("Play / Pause Recording", systemImage: "playpause") {
                        if player.rate > 0 { player.pause() } else { play(session) }
                    }
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        Text(Self.clock(player.currentTime().seconds)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            if let playbackError { Text(verbatim: playbackError).foregroundStyle(.orange) }
        }
    }

    private func play(_ session: MeetingSession, at time: Double? = nil) {
        let url = meetings.playbackURL(for: session.id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            playbackError = String(localized: "The playback recording is not ready. Process the saved recording first.")
            return
        }
        if player.currentItem == nil { player.replaceCurrentItem(with: AVPlayerItem(url: url)) }
        if let time { player.seek(to: CMTime(seconds: time, preferredTimescale: 16_000), toleranceBefore: .zero, toleranceAfter: .zero) }
        player.play()
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.vertical, 6)
            Text("Recent meetings").font(.headline)
            if meetings.recent.isEmpty {
                Text("Record a call or a conversation. Get a private summary, action items and a transcript.")
                    .foregroundStyle(.secondary)
            }
            ForEach(meetings.recent) { session in
                Button {
                    meetings.endPreview()
                    meetings.selectedID = session.id
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: session.kind == .videoCall ? "headphones" : "person.2")
                            .foregroundStyle(Color.pencil)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: session.title).fontWeight(.medium).lineLimit(1)
                            Text("\(session.recorded.formatted(date: .abbreviated, time: .shortened)) · \(Self.clock(session.duration))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(stage(session)).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stage(_ session: MeetingSession) -> LocalizedStringResource {
        if session.reviewed { return "Reviewed" }
        switch session.stage {
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .saved: return "Saved locally"
        case .transcribing: return "Transcribing"
        case .writing: return "Writing"
        case .ready: return "Needs review"
        case .failed: return "Needs attention"
        }
    }

    private static func clock(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, Int(seconds)) : 0
        return value >= 3_600 ? String(format: "%d:%02d:%02d", value / 3_600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct MeetingProse: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("## ") {
                    Text(String(line.dropFirst(3))).font(.headline).padding(.top, 8)
                } else if !line.isEmpty {
                    Text(.init(line)).font(.system(.body, design: .serif)).textSelection(.enabled)
                }
            }
        }
    }
}
