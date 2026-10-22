import APAudio
import APCore
import APStorage
import APTranscription
import Foundation
import Observation
import UIKit
import UserNotifications

/// Turns recordings into vault notes: audio saved on the iPhone, the transcript written in a style, then
/// filed straight away as needs-review (reviewing happens on the Obsidian board, as on the Mac).
@Observable
final class PhoneNotes {
    private(set) var recent: [RecentNote] = []
    /// What processing is doing right now, if anything.
    private(set) var processing: String?

    @ObservationIgnored private unowned let app: PhoneModel
    @ObservationIgnored private let folder: URL

    init(app: PhoneModel) {
        self.app = app
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appending(path: "AudioPencil/Pending", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        recent = (try? JSONDecoder().decode([RecentNote].self, from: Data(contentsOf: folder.appending(path: "recent.json")))) ?? []
        queue = (try? JSONDecoder().decode([QueuedRecording].self, from: Data(contentsOf: folder.appending(path: "queue.json")))) ?? []
        fileLeftoverReviews()
        watchAppState()
    }

    /// Notes from before filing became immediate were held for review: file them as they were.
    private func fileLeftoverReviews() {
        let saved = folder.appending(path: "pending.json")
        guard let leftovers = try? JSONDecoder().decode([PendingNote].self, from: Data(contentsOf: saved)) else { return }
        try? FileManager.default.removeItem(at: saved)
        for item in leftovers {
            var note = item.note
            note.tags += item.newTags.filter { !note.tags.contains($0) }
            Task { await file(note, audio: item.audioFile.map { folder.appending(path: $0) }) }
        }
    }

    /// A recording waiting to be written up: saved on this iPhone (audio and transcript) until its note is filed.
    struct QueuedRecording: Codable, Identifiable {
        var id: UUID
        var transcript: String
        var language: String
        var recorded: Date
        var duration: TimeInterval
        var styleID: String
        var audioFile: String?
        /// Meeting mode (optional: recordings queued before it existed decode as plain notes).
        var meeting: Bool?
        var speakers: Int?
    }

    /// Recordings waiting to be written up, oldest first.
    private(set) var queue: [QueuedRecording] = []
    @ObservationIgnored private var processTask: Task<Void, Never>?
    /// Meeting mode's speaker labels (small models, loaded only while labelling).
    @ObservationIgnored private let speakerLabeler = SpeakerLabeler()
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    /// The writing model runs on the GPU, which iOS only allows while the app is on screen. So notes are
    /// written while Audio Pencil is open; leaving stops the current one (it starts again on return), and
    /// a recording stopped from the Lock Screen waits here until the app is next opened.
    private func watchAppState() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pauseProcessing() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.processQueue() }
        })
    }

    /// From the style sheet after an in-app stop.
    func make(_ capture: PhoneCapture, style: Style) {
        enqueue(capture, style: style)
    }

    /// Saves the recording (audio and transcript) and writes it up now if the app is open, or later if not.
    func enqueue(_ capture: PhoneCapture, style: Style) {
        let id = UUID()
        let audioName = "\(id.uuidString).m4a"
        let audioURL = folder.appending(path: audioName)
        processing = String(localized: "Saving the audio…")
        let background = UIApplication.shared.beginBackgroundTask(withName: "Saving a recording")
        Task {
            defer { UIApplication.shared.endBackgroundTask(background) }
            let samples = capture.samples
            let savedAudio = await Task.detached(priority: .userInitiated) { () -> Bool in
                (try? AudioFileWriter.writeM4A(samples: samples, to: audioURL)) != nil
            }.value
            queue.append(QueuedRecording(
                id: id, transcript: capture.transcript, language: capture.language.code, recorded: capture.recorded,
                duration: capture.duration, styleID: style.id, audioFile: savedAudio ? audioName : nil,
                meeting: capture.meeting, speakers: capture.speakers
            ))
            saveQueue()
            processing = nil
            if UIApplication.shared.applicationState == .active {
                processQueue()
            } else {
                Self.notify(
                    title: String(localized: "Recording saved"),
                    body: String(localized: "Open Audio Pencil to write it up as \(style.displayName).")
                )
            }
        }
    }

    /// Writes and files queued recordings one at a time, while the app is open and not recording.
    func processQueue() {
        guard processTask == nil, !queue.isEmpty, !app.recorder.isActive,
              UIApplication.shared.applicationState == .active
        else { return }
        processTask = Task {
            while let item = queue.first, !Task.isCancelled {
                guard await process(item) else { break } // stopped part-way: stays queued
                queue.removeFirst()
                saveQueue()
            }
            processing = nil
            processTask = nil
        }
    }

    func pauseProcessing() {
        guard let processTask else { return }
        processTask.cancel()
        Log.dictation.notice("Note writing paused: the app left the screen")
    }

    /// True once the note is filed; false if writing was stopped part-way.
    private func process(_ item: QueuedRecording) async -> Bool {
        // "New task: book the dentist" → a one-line task note, as said (no writing model needed).
        if item.meeting != true, let task = TaskKeywords.remainder(of: item.transcript, keywords: app.taskKeywords) {
            let style = app.styles.first { $0.id == item.styleID } ?? app.lastStyle
            let note = Note(
                id: item.id,
                title: NoteRenderer.fallbackTitle(from: task),
                styleID: style.id,
                status: .needsReview,
                recorded: item.recorded,
                duration: item.duration,
                device: "iphone",
                mode: .quick,
                folder: folder(for: style),
                language: item.language,
                body: TaskLine.make(task, said: item.recorded, language: item.language)
            )
            processing = String(localized: "Filing the note…")
            await file(note, audio: item.audioFile.map { folder.appending(path: $0) })
            return true
        }
        let style = app.styles.first { $0.id == item.styleID } ?? app.lastStyle
        let language = SpokenLanguage(code: item.language)
        let waiting = queue.count - 1
        var labelled: SpeakerTranscript?
        if item.meeting == true, let audio = item.audioFile.map({ folder.appending(path: $0) }) {
            processing = String(localized: "Labelling the speakers…")
            labelled = await labelSpeakers(audio, language: language, speakers: item.speakers)
            if Task.isCancelled { return false }
        }
        let label = SpeakerTranscript.label
        let transcript = labelled?.text(label: label) ?? item.transcript
        let result = await app.processLongForm(transcript: transcript, style: style, language: language, speakerLabel: labelled == nil ? nil : label, said: item.recorded) { [weak self] status in
            self?.processing = waiting > 0 ? String(localized: "\(status) (\(waiting) more waiting)") : status
        }
        // Writing stops when the app leaves the screen, and then returns the plain transcript: don't file that.
        if Task.isCancelled { return false }
        // Suggested tags are used as they are; new ones join the vault's tag list.
        let added = result.newTags.filter { !app.tags.contains($0) }
        if !added.isEmpty { app.tags += added }
        let note = Note(
            id: item.id,
            title: result.title ?? NoteRenderer.fallbackTitle(from: item.transcript),
            styleID: style.id,
            status: .needsReview,
            recorded: item.recorded,
            duration: item.duration,
            device: "iphone",
            mode: labelled == nil ? .longForm : .meeting,
            tags: result.knownTags + added,
            folder: folder(for: style),
            language: item.language,
            // A meeting note that wasn't written up (raw, or no writing model) is the labelled transcript;
            // written ones keep it below.
            body: labelled.map { result.body == transcript ? $0.markdown(label: label) : result.body } ?? result.body,
            transcript: labelled.map { result.body == transcript ? nil : $0.markdown(label: label) } ?? (keepsTranscript(style) ? item.transcript : nil),
            speakers: labelled?.speakerCount
        )
        processing = String(localized: "Filing the note…")
        await file(note, audio: item.audioFile.map { folder.appending(path: $0) })
        return true
    }

    /// Who said what in a meeting recording: Whisper again over the whole audio with word timings, and the
    /// speaker model. Nil (a plain note) if that can't be done.
    private func labelSpeakers(_ audio: URL, language: SpokenLanguage, speakers: Int?) async -> SpeakerTranscript? {
        do {
            let samples = try await Task.detached(priority: .userInitiated) { try AudioFileReader.readMono(audio) }.value
            // The recording's language may need the other Whisper model than the one loaded now.
            let variant = SpeechModels.bestVariant(for: language, settings: app.settings)
            let engine = variant == app.whisper.variant ? app.whisper : WhisperEngine(variant: variant)
            guard engine.isDownloaded else { return nil }
            try await app.coordinator.ensureLoaded(engine)
            await engine.setLanguage(language.code)
            let labelled = try await speakerLabeler.transcribe(samples, with: engine, speakers: speakers)
            await speakerLabeler.unload()
            if engine !== app.whisper { app.prepareModel() } // the coordinator swapped the app's model out
            return labelled
        } catch {
            Log.dictation.error("Speaker labels failed: \(error.localizedDescription, privacy: .public)")
            await speakerLabeler.unload()
            return nil
        }
    }

    private func saveQueue() {
        if let data = try? JSONEncoder().encode(queue) { try? data.write(to: folder.appending(path: "queue.json"), options: .atomic) }
    }

    /// A local notification (the app asks for permission when the first recording starts).
    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func file(_ note: Note, audio: URL?) async {
        let styleName = app.styles.first { $0.id == note.styleID }?.displayName ?? note.styleID
        do {
            let filed = try await NoteFiling.queue(note, audio: audio, outbox: app.sync.outbox, layout: app.vault.layout ?? .plain)
            recent.insert(RecentNote(id: note.id, title: note.title, styleName: styleName, recorded: note.recorded, path: filed.path, status: note.status), at: 0)
            recent = Array(recent.prefix(50))
            saveRecent()
            Log.dictation.notice("Note queued: \(filed.path, privacy: .public)")
            app.sync.syncSoon(after: .zero)
        } catch {
            Log.dictation.error("Couldn't queue the note: \(error.localizedDescription, privacy: .public)")
        }
    }

    func folder(for style: Style) -> String {
        guard let folder = style.folder?.trimmingCharacters(in: .whitespaces), !folder.isEmpty else { return NoteFiling.defaultFolder }
        return StoragePath.join(folder)
    }

    /// Rewritten notes keep the raw transcript under a Transcript heading; tidy and raw ones don't need it.
    private func keepsTranscript(_ style: Style) -> Bool {
        !style.isRaw && style.intensity != .light
    }

    private func saveRecent() {
        if let data = try? JSONEncoder().encode(recent) { try? data.write(to: folder.appending(path: "recent.json"), options: .atomic) }
    }
}
