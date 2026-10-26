import APAudio
import APCore
import AVFoundation
import SwiftUI
import UIKit

struct MobileMeetingsView: View {
    let app: PhoneModel
    @Bindable var meetings: MeetingController
    @State private var compactColumn = NavigationSplitViewColumn.detail
    @State private var section = ReviewSection.summary
    @State private var discarding = false
    @State private var deleting = false
    @State private var player = AVPlayer()
    @State private var playbackError: String?
    @State private var playing = false
    @State private var copiedMeeting = false
    /// The recording clock follows the text size, as on Record.
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 44

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
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            List(selection: $meetings.selectedID) {
                Button("New Meeting", systemImage: "plus") {
                    meetings.selectedID = nil
                    compactColumn = .detail
                }
                ForEach(meetings.recent) { session in
                    NavigationLink(value: session.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: session.title).font(.system(.body, design: .serif))
                            Text(session.recorded, format: .dateTime.month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                            Text(session.reviewed ? "Reviewed" : session.stage == .ready ? "Needs review" : "Saved on this device")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .disabled(meetings.ownsCapture)
            .navigationTitle("Meetings")
            .overlay {
                if meetings.recent.isEmpty {
                    ContentUnavailableView("No meetings yet", systemImage: "person.2",
                                           description: Text("Start a conversation recording. It stays on this device until you file it."))
                        .allowsHitTesting(false)
                }
            }
        } detail: {
            NavigationStack {
                Group {
                    if meetings.ownsCapture { recording }
                    else if let session = meetings.selected { review(session) }
                    else { setup }
                }
                .navigationTitle(meetings.selected == nil ? "New Meeting" : "Meeting")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if meetings.selected != nil, !meetings.ownsCapture {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("New Meeting", systemImage: "plus") { meetings.selectedID = nil }
                        }
                    }
                }
            }
        }
        .onChange(of: meetings.selectedID) { _, _ in
            compactColumn = .detail
            pausePlayback()
            player.replaceCurrentItem(with: nil)
            playbackError = nil
        }
        .onChange(of: app.recorder.isActive) { _, active in if active { pausePlayback() } }
        .onDisappear { pausePlayback() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem, item === player.currentItem else { return }
            playing = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem, item === player.currentItem else { return }
            playbackError = item.error?.localizedDescription ?? String(localized: "The recording could not be played.")
        }
        .confirmationDialog("Discard this meeting recording?", isPresented: $discarding) {
            Button("Discard Recording", role: .destructive) { Task { await meetings.stop(discard: true) } }
        } message: {
            Text("The local recording will be permanently deleted.")
        }
        .confirmationDialog("Delete this local meeting?", isPresented: $deleting) {
            Button("Delete Local Meeting", role: .destructive) {
                if let id = meetings.selectedID { meetings.delete(id) }
            }
        } message: {
            Text("Local audio and review data will be permanently deleted. A note already filed in your storage stays there.")
        }
    }

    private var setup: some View {
        Form {
            errors
            Section {
                TextField("Meeting title (optional)", text: $meetings.title)
                Picker("Language", selection: $meetings.language) {
                    ForEach(app.offeredLanguages) { language in
                        Text(verbatim: language.name()).tag(language)
                    }
                }
                Picker("Speakers", selection: $meetings.speakerHint) {
                    Text("Automatic").tag(Int?.none)
                    ForEach(2...6, id: \.self) { Text("\($0) people").tag(Optional($0)) }
                }
                Toggle("Process after recording", isOn: $meetings.processAfterRecording)
                if app.sync.dailyNotes == .on {
                    Toggle("Link in today's daily note", isOn: $meetings.dailyNote)
                }
            } header: {
                Text("In-person conversation")
            } footer: {
                Text("Records the people in the room through the current microphone (a headset or USB input too), not audio from another app. Processing transcribes it, labels who spoke and writes a summary, on this device, while Audio Pencil is open.")
            }
            if !app.whisper.isDownloaded || !app.writingModelDownloaded {
                Section {
                    NavigationLink {
                        ModelsSettingsView(app: app)
                    } label: {
                        Label("Get the speech and writing models", systemImage: "arrow.down.circle")
                    }
                } footer: {
                    Text("You can record now and process once they're on this device.")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if app.recorder.isActive { Text("Finish the current recording first.").font(.callout) }
                if meetings.isProcessing { Text("Wait for meeting processing to finish.").font(.callout) }
                if let processing = app.notes.processing { Text(verbatim: processing).font(.callout) }
                // Said where the decision is made, not below the fold.
                Text("Make sure everyone knows they're being recorded. Audio Pencil doesn't tell them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    pausePlayback()
                    Task { await meetings.start() }
                } label: {
                    Label("Start Meeting", systemImage: "record.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(app.recorder.isActive || meetings.isProcessing || app.notes.processing != nil)
            }
            .padding()
            .background(.bar)
        }
        .onAppear {
            meetings.language = app.currentLanguage
            meetings.dailyNote = app.settings.dailyNoteLinks
        }
    }

    /// The same instrument as Record: round controls, a big clock and the level, so a meeting is recorded
    /// the way everything else is. Title and microphone sit quietly above.
    private var recording: some View {
        VStack(spacing: 0) {
            if let error = meetings.error {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(verbatim: error).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss Message", systemImage: "xmark") { meetings.clearError() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: meetings.selected?.title ?? String(localized: "Meeting"))
                    .font(.system(.title2, design: .serif))
                Label(captureStatus, systemImage: meetings.capture == .paused ? "pause.circle.fill" : "record.circle")
                    .font(.callout)
                    .foregroundStyle(meetings.capture == .paused ? Color.orange : Color.secondary)
                if let microphone = meetings.selected?.microphoneName {
                    Text(verbatim: microphone).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            Spacer()
            VStack(spacing: 18) {
                MeetingLevelBars(level: meetings.capture == .recording ? meetings.microphoneLevel : 0)
                    .opacity(meetings.capture == .recording ? 1 : 0.35)
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Text(PreparationStatus.clock(meetings.elapsed(at: context.date)))
                        .font(.system(size: clockSize, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(meetings.capture == .paused ? .secondary : .primary)
                        .contentTransition(.numericText())
                }
                .accessibilityLabel(Text("Recorded time"))
                HStack(spacing: 36) {
                    CircleButton(symbol: "xmark", label: "Discard recording", size: 56, prominent: false) { discarding = true }
                    if meetings.capture == .starting || meetings.capture == .stopping {
                        ProgressView().controlSize(.large).frame(width: 88, height: 88)
                    } else {
                        CircleButton(symbol: "stop.fill", label: "Stop and save the meeting", size: 88, prominent: true) {
                            Task { await meetings.stop() }
                        }
                    }
                    CircleButton(
                        symbol: meetings.capture == .paused ? "play.fill" : "pause.fill",
                        label: meetings.capture == .paused ? "Resume" : "Pause",
                        size: 56,
                        prominent: false
                    ) {
                        Task { await meetings.togglePause() }
                    }
                }
                .disabled(meetings.capture == .starting || meetings.capture == .stopping)
            }
            Text("Keeps recording with the device locked or the app in the background. A call or a disconnected microphone pauses it; resume here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
        }
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
    }

    private var captureStatus: LocalizedStringResource {
        switch meetings.capture {
        case .starting: "Starting the microphone…"
        case .paused: "Paused"
        case .stopping: "Saving…"
        case .idle, .recording: "Recording"
        }
    }

    @ViewBuilder private var errors: some View {
        if let error = meetings.error {
            Section {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).textSelection(.enabled)
                Button("Dismiss Message") { meetings.clearError() }
            }
        }
    }

    private func review(_ session: MeetingSession) -> some View {
        List {
            errors
            Section {
                TextField("Meeting title", text: Binding(get: { meetings.selected?.title ?? session.title },
                                                       set: { meetings.update(session.id, title: $0) }))
                    .font(.system(.title2, design: .serif))
                    .disabled(meetings.isProcessing)
                Text("\(session.recorded.formatted(date: .abbreviated, time: .shortened)) · \(PreparationStatus.clock(session.duration))")
                    .foregroundStyle(.secondary)
                Text(meetings.filingStatus(session)).font(.callout).foregroundStyle(.secondary)
                if session.retention == .archive {
                    Label("Audio kept forever", systemImage: "infinity").font(.callout).foregroundStyle(.secondary)
                }
                if meetings.processingID == session.id {
                    ProgressView(meetings.progress)
                } else if session.processingRequested {
                    Label("Waiting to process while the app is open and not recording.", systemImage: "clock")
                } else if session.stage == .saved || session.stage == .failed {
                    if let error = session.error { Text(verbatim: error).foregroundStyle(.orange) }
                    // What's needed next; starting over from the transcript lives in the ··· menu.
                    Button(session.turns.isEmpty ? "Process Saved Recording" : "Retry Summary") {
                        meetings.process(session.id, retrySummaryOnly: !session.turns.isEmpty)
                    }
                    .disabled(meetings.isProcessing || app.recorder.isActive)
                }
                ForEach(Array(Set(session.warnings)).sorted(), id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
                }
            }
            if FileManager.default.fileExists(atPath: meetings.playbackURL(for: session.id).path) {
                Section {
                    Button(playing ? "Pause Recording" : "Play Recording", systemImage: playing ? "pause.fill" : "play.fill") {
                        if playing { pausePlayback() } else { play(session) }
                    }
                    .disabled(app.recorder.isActive)
                    if let playbackError { Text(verbatim: playbackError).foregroundStyle(.orange) }
                }
            }
            if !session.turns.isEmpty {
                Section {
                    Picker("Review", selection: $section) {
                        ForEach(ReviewSection.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch section {
                    case .summary:
                        if session.summary.isEmpty {
                            Text("The transcript is saved. A summary will appear after processing.")
                                .foregroundStyle(.secondary)
                        } else {
                            MeetingSummaryText(text: session.displayingSpeakerNames(in: session.summary))
                        }
                    case .actions:
                        Text("Edit tasks, owners and dates as Markdown. Leave unknown owners and deadlines unset.")
                            .font(.footnote).foregroundStyle(.secondary)
                        TextEditor(text: Binding(get: { meetings.selected?.actions ?? session.actions },
                                                 set: { meetings.update(session.id, actions: $0) }))
                            .frame(minHeight: 200)
                            .accessibilityLabel("Meeting action items")
                            .disabled(meetings.isProcessing)
                    case .transcript:
                        DisclosureGroup("Speaker names") {
                            ForEach(Set(session.turns.map(\.speaker)).sorted(), id: \.self) { speaker in
                                TextField(speaker, text: Binding(get: { meetings.selected?.speakerNames[speaker] ?? "" },
                                                                set: { meetings.update(session.id, speaker: speaker, name: $0) }))
                                    .accessibilityLabel(Text("Name for \(speaker)"))
                            }
                        }
                        .disabled(meetings.isProcessing)
                        ForEach(session.turns) { turn in
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    play(session, at: turn.start)
                                } label: {
                                    Text("\(PreparationStatus.clock(turn.start)) · \(session.speakerName(turn.speaker))")
                                        .font(.headline).frame(minHeight: 44)
                                }
                                .buttonStyle(.borderless)
                                .disabled(app.recorder.isActive || session.audioExpired)
                                Text(verbatim: turn.text).font(.system(.body, design: .serif)).textSelection(.enabled)
                            }
                        }
                    }
                }
                Section {
                    // The one thing to do here: put it (or the edits) in storage.
                    Button {
                        Task { await meetings.file(session.id) }
                    } label: {
                        Label(session.notePath == nil ? "File Note" : "Update Filed Note", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                .disabled(meetings.isProcessing || meetings.filing)
                Section {
                    if !session.reviewed {
                        Button("Mark Reviewed", systemImage: "checkmark.circle") {
                            meetings.update(session.id, reviewed: true)
                            // A filed note carries its review status: keep it in step.
                            if session.notePath != nil { Task { await meetings.file(session.id) } }
                        }
                    } else {
                        Label("Reviewed", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                    }
                    Button(copiedMeeting ? "Copied" : "Copy Meeting Note", systemImage: copiedMeeting ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = session.displayingSpeakerNames(in: session.body) + "\n\n" + session.transcript
                        copiedMeeting = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copiedMeeting = false
                        }
                    }
                    .sensoryFeedback(.success, trigger: copiedMeeting) { _, new in new }
                    if let path = session.notePath, let url = app.vault.obsidianURL(for: path) {
                        Link(destination: url) { Label("Open in Obsidian", systemImage: "arrow.up.forward.app") }
                    }
                } footer: {
                    if session.notePath != nil, !session.reviewed {
                        Text("Marking it reviewed also updates the filed note.")
                    }
                }
                .disabled(meetings.isProcessing || meetings.filing)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis.circle") {
                    if !session.turns.isEmpty {
                        Button("Transcribe Again", systemImage: "arrow.clockwise") { meetings.process(session.id) }
                            .disabled(meetings.isProcessing || app.recorder.isActive)
                    }
                    if session.retention != .archive {
                        Button("Keep Audio Forever", systemImage: "infinity") { meetings.keepForever(session.id) }
                            .disabled(session.audioExpired || meetings.filing)
                    }
                    Button("Delete Local Meeting…", systemImage: "trash", role: .destructive) { deleting = true }
                }
                .disabled(meetings.isProcessing || meetings.filing)
            }
        }
    }

    private func pausePlayback() {
        player.pause()
        playing = false
    }

    private func play(_ session: MeetingSession, at time: Double? = nil) {
        guard !app.recorder.isActive, !meetings.ownsCapture else { return }
        let url = meetings.playbackURL(for: session.id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            playbackError = String(localized: "Process the saved recording to prepare playback.")
            return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback)
            try audio.setActive(true)
            if player.currentItem == nil { player.replaceCurrentItem(with: AVPlayerItem(url: url)) }
            if let time { player.seek(to: CMTime(seconds: time, preferredTimescale: 16_000)) }
            player.play()
            playing = true
        } catch { playbackError = error.localizedDescription }
    }
}

private struct MeetingSummaryText: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("## ") {
                    Text(String(line.dropFirst(3))).font(.headline)
                } else if !line.isEmpty {
                    Text(.init(line)).font(.system(.body, design: .serif)).textSelection(.enabled)
                }
            }
        }
    }
}

/// The microphone level as Record-style bars, newest on the right.
private struct MeetingLevelBars: View {
    let level: Float
    @State private var history = [Float](repeating: 0, count: 16)

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(history.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.pencil)
                    .frame(width: 4, height: 6 + CGFloat(min(max(history[index], 0), 1)) * 34)
            }
        }
        .frame(height: 42)
        .animation(.linear(duration: 0.08), value: history)
        .onChange(of: level) { _, new in
            history.removeFirst()
            history.append(new)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Microphone level"))
        .accessibilityValue(Text(level < 0.05 ? "Quiet" : level < 0.4 ? "Speaking" : "Loud"))
    }
}
