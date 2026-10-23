import APAudio
import APCore
import AVFoundation
import SwiftUI
import UIKit

struct MobileMeetingsView: View {
    let app: PhoneModel
    @Bindable var meetings: MeetingController
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var compactColumn = NavigationSplitViewColumn.detail
    @State private var section = ReviewSection.summary
    @State private var discarding = false
    @State private var deleting = false
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
                    if sizeClass == .compact, !meetings.ownsCapture {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Recent meetings", systemImage: "clock") { compactColumn = .sidebar }
                        }
                    }
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
            player.pause()
            player.replaceCurrentItem(with: nil)
            playbackError = nil
        }
        .onChange(of: app.recorder.isActive) { _, active in if active { player.pause() } }
        .onDisappear { player.pause() }
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
            Section("In-person conversation") {
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
            }
            Section {
                Label("Uses the current system microphone, including a connected headset or USB audio input.", systemImage: "mic")
                Label("Records people in the room, not audio from another app.", systemImage: "person.2")
                Label("Saved on this device. Transcription and summaries run while Audio Pencil is open.", systemImage: "lock")
                if !app.whisper.isDownloaded || !app.writingModelDownloaded {
                    Text("You can record now and process later. Download speech and writing models in Settings before processing.")
                }
            }
            .font(.callout).foregroundStyle(.secondary)
            Section {
                Text("Make sure everyone knows this meeting is being recorded. Audio Pencil does not notify participants.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if app.recorder.isActive { Text("Finish the current recording first.").font(.callout) }
                if meetings.isProcessing { Text("Wait for meeting processing to finish.").font(.callout) }
                if let processing = app.notes.processing { Text(verbatim: processing).font(.callout) }
                Button {
                    player.pause()
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

    private var recording: some View {
        Form {
            errors
            Section {
                if let session = meetings.selected {
                    Text(verbatim: session.title).font(.system(.title2, design: .serif))
                    Label(meetings.capture == .paused ? "Paused" : meetings.capture == .starting ? "Starting…" : "Recording",
                          systemImage: meetings.capture == .paused ? "pause.circle" : "record.circle")
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(PreparationStatus.clock(meetings.elapsed(at: context.date)))
                            .font(.largeTitle.monospacedDigit())
                            .accessibilityLabel("Recorded time")
                    }
                    Text(verbatim: session.microphoneName).foregroundStyle(.secondary)
                    ProgressView(value: Double(meetings.microphoneLevel))
                        .accessibilityLabel("Microphone level")
                        .accessibilityValue(Text("\(Int(meetings.microphoneLevel * 100)) percent"))
                } else { ProgressView("Starting the microphone…") }
            }
            Section {
                Button(meetings.capture == .paused ? "Resume Recording" : "Pause Recording",
                       systemImage: meetings.capture == .paused ? "play" : "pause") {
                    Task { await meetings.togglePause() }
                }
                Button("Stop and Save Meeting", systemImage: "stop.fill") { Task { await meetings.stop() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Discard Recording…", role: .destructive) { discarding = true }
            } footer: {
                Text("Recording continues if you lock the device or leave the app. An interruption or disconnected microphone pauses it; return here to resume.")
            }
            .disabled(meetings.capture == .starting || meetings.capture == .stopping)
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
                if meetings.processingID == session.id {
                    ProgressView(meetings.progress)
                } else if session.processingRequested {
                    Label("Waiting to process while the app is open and not recording.", systemImage: "clock")
                } else if session.stage == .saved || session.stage == .failed {
                    if let error = session.error { Text(verbatim: error).foregroundStyle(.orange) }
                    Button(session.turns.isEmpty ? "Process Saved Recording" : "Retry Summary") {
                        meetings.process(session.id, retrySummaryOnly: !session.turns.isEmpty)
                    }
                    .disabled(meetings.isProcessing || app.recorder.isActive)
                    if !session.turns.isEmpty {
                        Button("Retry Transcription") { meetings.process(session.id) }
                            .disabled(meetings.isProcessing || app.recorder.isActive)
                    }
                }
                ForEach(Array(Set(session.warnings)).sorted(), id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
                }
            }
            if FileManager.default.fileExists(atPath: meetings.playbackURL(for: session.id).path) {
                Section {
                    Button("Play / Pause Recording", systemImage: "playpause") {
                        if player.rate > 0 { player.pause() } else { play(session) }
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
                    Button(session.reviewed ? "Reviewed" : "Mark Reviewed", systemImage: "checkmark.circle") {
                        meetings.update(session.id, reviewed: true)
                        Task { await meetings.file(session.id) }
                    }
                    Button("File / Update Note", systemImage: "folder") { Task { await meetings.file(session.id) } }
                    Button("Copy Meeting Note", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = session.displayingSpeakerNames(in: session.body) + "\n\n" + session.transcript
                    }
                    if let path = session.notePath, let url = app.vault.obsidianURL(for: path) {
                        Link("Open in Obsidian", destination: url)
                    }
                }
                .disabled(meetings.isProcessing || meetings.filing)
            }
            Section {
                if session.retention != .archive {
                    Button("Keep Audio Forever") { meetings.keepForever(session.id) }
                        .disabled(session.audioExpired || meetings.filing)
                } else { Label("Audio kept forever", systemImage: "infinity") }
                Button("Delete Local Meeting…", role: .destructive) { deleting = true }
            }
            .disabled(meetings.isProcessing || meetings.filing)
        }
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
