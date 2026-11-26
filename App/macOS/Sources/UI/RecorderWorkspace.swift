import APAudio
import APCore
import APStorage
import SwiftUI

struct RecorderWorkspace: View {
    let app: AppModel
    @State private var showsAll = false
    @State private var deleting: SavedRecording?

    private var library: RecorderController { app.recordings }
    private var active: Bool { app.dictation.isActive }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = library.error {
                HStack(alignment: .top) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).textSelection(.enabled)
                    Spacer()
                    Button { library.error = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss recording error")
                }
                .padding(12)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .id("recordingError")
            }
            if !library.interrupted.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(Color.pencil)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("A recording was interrupted.").font(.headline)
                        Text("Saved audio is ready to listen to or transcribe. Audio that hadn't reached disk can't be recovered.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Review Recording") { library.selectedID = library.interrupted.first?.id }
                }
                .padding(14)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            }
            recordingPanel
            Text("Stop to keep the recording. Listen and transcribe whenever you're ready. Push-to-talk isn't saved.")
                .font(.caption).foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text("Recent recordings").font(.headline)
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.open(library.root) }
                    .buttonStyle(.link).font(.callout)
            }
            if library.recordings.isEmpty {
                ContentUnavailableView {
                    Label("Your next thought starts here.", systemImage: "waveform")
                } description: {
                    Text("Record above or import an audio file. You can listen before making a transcript.")
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array((showsAll ? library.recordings : Array(library.recordings.prefix(10))).enumerated()), id: \.element.id) { index, recording in
                        if index > 0 { Divider() }
                        row(recording)
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                if library.recordings.count > 10 {
                    Button(showsAll ? "Show Recent Only" : "Show All Recordings") { showsAll.toggle() }
                        .buttonStyle(.link)
                }
            }
            if let recording = library.selected, recording.status != .capturing {
                RecordingReview(app: app, recording: recording, deleting: $deleting)
                    .id(recording.id)
                    .id("recordingReview")
            }
            if let progress = library.progress {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.callout)
                    Spacer()
                    if library.processingID != nil {
                        Button("Cancel Processing") { library.cancelProcessing() }
                    }
                }
            }
        }
        .confirmationDialog("Delete this recording?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let deleting {
                Button("Delete Recording", role: .destructive) { library.delete(deleting.id); self.deleting = nil }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("The local audio and transcript go to the Trash. Any note already filed in your storage stays there.")
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 1, let url = urls.first, url.isFileURL, !active, !library.isWorking else { return false }
            library.importAudio(url)
            return true
        }
    }

    private var recordingPanel: some View {
        Card {
            HStack {
                Label(captureLabel, systemImage: active ? (app.dictation.isPaused ? "pause.fill" : "record.circle.fill") : "mic")
                    .font(.headline)
                    .foregroundStyle(active && !app.dictation.isPaused ? Color.red : Color.primary)
                Spacer()
                Label("On this Mac", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
            }
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Duration.seconds(active ? app.dictation.recordedSeconds : 0).formatted(.time(pattern: .minuteSecond)))
                            .font(.system(size: 44, weight: .medium, design: .rounded)).monospacedDigit()
                        Text(active ? (app.dictation.isPaused ? "Take your time. Capture is paused." : "Take your time. The recorder is listening.") : "A little space to think out loud.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    HStack(alignment: .center, spacing: 4) {
                        ForEach(Array(app.indicator.levels.enumerated()), id: \.offset) { _, level in
                            Capsule().fill(active ? Color.pencil : Color.secondary.opacity(0.5))
                                .frame(width: 3, height: active ? max(3, CGFloat(level) * 55) : 3)
                        }
                    }
                    .frame(height: 65).accessibilityHidden(true)
                }
                .padding(.vertical, 16)
            }
            Divider()
            HStack {
                Label(app.currentMicrophoneName, systemImage: "mic")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if !active {
                    Button("Change…") { app.settingsTab = .dictation; app.page = .settings }.buttonStyle(.link)
                } else {
                    Text(app.dictation.isPaused ? "Paused" : app.dictation.microphoneLevel > 0.01 ? "Input detected" : "No audio heard")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack { saveStatus; Spacer(); captureActions }
                VStack(alignment: .leading, spacing: 12) { saveStatus; HStack { Spacer(); captureActions } }
            }
        }
        .accessibilityIdentifier("recorderPanel")
    }

    private var captureLabel: LocalizedStringResource {
        switch app.dictation.phase {
        case .idle: "Ready to record"
        case .starting: "Starting the microphone…"
        case .finishing: "Finishing…"
        case .recording: app.dictation.isPaused ? "Paused" : app.indicator.isPushToTalk ? "Push to talk" : app.dictation.recorderOnly ? "Recording" : "Dictating"
        }
    }

    private var saveStatus: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 3) {
                if active && app.indicator.isPushToTalk {
                    Label("Temporary audio · not saved", systemImage: "clock")
                } else if active {
                    Label("Saving to this Mac · \(Duration.seconds(app.dictation.recordedSeconds).formatted(.time(pattern: .minuteSecond))) written",
                          systemImage: "checkmark.shield")
                } else {
                    Label("Audio saves to this Mac while you record.", systemImage: "checkmark.shield")
                }
                Text("Local recovery files stay until you delete them.").foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private var captureActions: some View {
        HStack(spacing: 8) {
            if app.dictation.phase == .recording {
                if app.dictation.recorderOnly {
                    Button(app.dictation.isPaused ? "Resume" : "Pause", systemImage: app.dictation.isPaused ? "play" : "pause") { app.dictation.togglePause() }
                }
                Button(app.dictation.recorderOnly ? "Stop & Keep" : "Stop Dictation", systemImage: "stop.fill") { app.dictation.stop() }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("stopRecording")
            } else if app.permissions.microphone != .granted {
                Button("Allow Microphone") { Task { await app.permissions.requestMicrophone() } }
            } else {
                Button("Record", systemImage: "record.circle.fill") { app.startRecording() }
                    .buttonStyle(.borderedProminent)
                    .disabled(active || library.isWorking || app.meetings.ownsCapture || app.meetings.isProcessing || app.notes.processing != nil)
                    .accessibilityIdentifier("startRecording")
            }
        }
    }

    private func row(_ recording: SavedRecording) -> some View {
        HStack(spacing: 12) {
            Image(systemName: recording.status == .interrupted ? "clock.arrow.circlepath" : recording.kind == .imported ? "doc" : "waveform")
                .foregroundStyle(recording.status == .interrupted ? Color.pencil : Color.secondary)
                .frame(width: 20)
            Button {
                library.stopPlayback()
                library.selectedID = recording.id
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(recording.title).font(.headline).lineLimit(1)
                    Text(recording.recorded, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if recording.status == .capturing {
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    Text(Duration.seconds(app.dictation.recordedSeconds).formatted(.time(pattern: .minuteSecond)))
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
            } else {
                Text(Duration.seconds(recording.duration).formatted(.time(pattern: .minuteSecond)))
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            if recording.status != .capturing {
                Button { library.play(recording.id) } label: {
                    Image(systemName: library.playingID == recording.id && library.player?.isPlaying == true ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel("Play or pause recording")
                .disabled(active || library.isWorking || recording.duration == 0)
                Button(recording.transcript == nil ? "Review" : "Open") { library.selectedID = recording.id }
            } else {
                Text(app.dictation.isPaused ? "Paused" : "Recording")
                    .font(.caption).foregroundStyle(app.dictation.isPaused ? Color.secondary : Color.red)
            }
        }
        .padding(13)
        .background(library.selectedID == recording.id ? Color.pencil.opacity(0.13) : Color.clear)
    }
}

struct RecorderActivityStatus: View {
    let app: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: app.dictation.isActive ? "record.circle.fill" : "waveform")
                .foregroundStyle(app.dictation.isActive ? Color.red : Color.pencil)
            Text(status).font(.callout)
            Spacer()
            Button("Show Recording") {
                app.page = .dictation
                NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil)
            }
            if app.dictation.phase == .recording {
                Button("Stop") { app.dictation.stop() }
            }
        }
    }

    private var status: String {
        if let progress = app.recordings.progress { return progress }
        if app.indicator.isPushToTalk { return String(localized: "Push to talk · temporary audio") }
        if app.dictation.isPaused { return String(localized: "Recording paused") }
        if app.dictation.phase == .finishing { return String(localized: "Finishing dictation…") }
        return String(localized: "Recording audio on this Mac")
    }
}

private struct RecordingReview: View {
    let app: AppModel
    let recording: SavedRecording
    @Binding var deleting: SavedRecording?
    @State private var styleID: String
    @State private var language: SpokenLanguage
    private var library: RecorderController { app.recordings }
    private var blocked: Bool { app.dictation.isActive || app.meetings.ownsCapture || app.meetings.isProcessing || library.isWorking || app.notes.processing != nil }

    init(app: AppModel, recording: SavedRecording, deleting: Binding<SavedRecording?>) {
        self.app = app
        self.recording = recording
        _deleting = deleting
        _styleID = State(initialValue: app.styles.contains { $0.id == recording.styleID } ? recording.styleID : Style.raw.id)
        _language = State(initialValue: SpokenLanguage(code: recording.language))
    }

    var body: some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recording.title).font(.headline).textSelection(.enabled)
                    Text(recording.status == .interrupted ? "Recovered audio" : recording.kind == .imported ? "Imported audio" : "Voice recording")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { library.stopPlayback(); library.selectedID = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("Close recording")
            }
            playback
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 12) { processingOptions; Spacer(); transcribeButton }
                VStack(alignment: .leading, spacing: 12) { processingOptions; transcribeButton }
            }
            if let body = recording.body {
                Divider()
                Text("Transcript").font(.headline)
                Text(body).font(.system(.title3, design: .serif)).lineSpacing(3).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let transcript = recording.transcript, transcript != body {
                    DisclosureGroup("Original transcript") {
                        Text(transcript).font(.system(.body, design: .serif)).textSelection(.enabled)
                    }
                }
                HStack {
                    Button("Copy Text", systemImage: "doc.on.doc") { app.dictation.paster.copy(body) }
                    Spacer()
                    if let path = recording.notePath {
                        Button("Open Filed Note") {
                            if let url = app.notes.openURL(for: path) { NSWorkspace.shared.open(url) }
                        }
                    } else {
                        Button("File as Note…", systemImage: "book.closed") { library.fileNote(recording.id) }
                            .disabled(blocked)
                    }
                }
            }
            Divider()
            HStack {
                Text("Transcription never changes the saved audio.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { library.export(recording.id) } label: { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel("Export audio").disabled(blocked || recording.duration == 0)
                Button(role: .destructive) { deleting = recording } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Delete recording").disabled(blocked)
            }
        }
    }

    private var playback: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            HStack(spacing: 10) {
                Button { library.play(recording.id) } label: {
                    Image(systemName: library.playingID == recording.id && library.player?.isPlaying == true ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel("Play or pause audio").disabled(blocked || recording.duration == 0)
                let player = library.playingID == recording.id ? library.player : nil
                Text(Duration.seconds(player?.currentTime ?? 0).formatted(.time(pattern: .minuteSecond)))
                    .font(.caption).monospacedDigit()
                Slider(value: Binding(get: { player?.currentTime ?? 0 }, set: { library.seek(to: $0) }),
                       in: 0...max(recording.duration, 0.01))
                    .accessibilityLabel("Playback position").disabled(player == nil)
                Text(Duration.seconds(recording.duration).formatted(.time(pattern: .minuteSecond)))
                    .font(.caption).monospacedDigit()
                Menu("\(Double(player?.rate ?? 1), format: .number.precision(.fractionLength(0...2)))×") {
                    ForEach([Float(1), 1.25, 1.5, 2], id: \.self) { speed in
                        Button("\(Double(speed), format: .number)×") { library.setSpeed(speed) }
                    }
                }
                .fixedSize().disabled(player == nil).accessibilityLabel("Playback speed")
            }
            .padding(.vertical, 8)
        }
    }

    private var processingOptions: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Language").font(.caption).foregroundStyle(.secondary)
                Picker("Language", selection: $language) {
                    ForEach(SpokenLanguage.all()) { language in Text(language.name()).tag(language) }
                }.labelsHidden().frame(maxWidth: 180)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Writing style").font(.caption).foregroundStyle(.secondary)
                Picker("Writing style", selection: $styleID) {
                    ForEach(app.styles) { style in Text(style.displayName).tag(style.id) }
                }.labelsHidden().frame(maxWidth: 180)
            }
        }
        .disabled(blocked)
    }

    private var transcribeButton: some View {
        Button(recording.transcript == nil ? "Transcribe" : "Process Again", systemImage: "pencil.and.scribble") {
            library.transcribe(recording.id, style: app.styles.first { $0.id == styleID } ?? .raw, language: language)
        }
        .buttonStyle(.borderedProminent)
        .disabled(blocked || recording.duration == 0)
        .accessibilityIdentifier("transcribeRecording")
    }
}
