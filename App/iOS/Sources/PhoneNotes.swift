import APAudio
import APCore
import APStorage
import Foundation
import Observation
import UIKit

/// Turns recordings into vault notes: audio saved on the iPhone, the transcript written in a style,
/// a review, then the note and its audio handed to the upload queue.
@Observable
final class PhoneNotes {
    private(set) var pending: [PendingNote] = []
    private(set) var recent: [RecentNote] = []
    /// What processing is doing right now, if anything.
    private(set) var processing: String?
    /// The note being reviewed (shown as a sheet).
    var reviewing: PendingNote?

    @ObservationIgnored private unowned let app: PhoneModel
    @ObservationIgnored private let folder: URL

    init(app: PhoneModel) {
        self.app = app
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appending(path: "AudioPencil/Pending", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        pending = (try? JSONDecoder().decode([PendingNote].self, from: Data(contentsOf: folder.appending(path: "pending.json")))) ?? []
        recent = (try? JSONDecoder().decode([RecentNote].self, from: Data(contentsOf: folder.appending(path: "recent.json")))) ?? []
    }

    /// Saves the audio, writes the note in `style`, then opens the review.
    func make(_ capture: PhoneCapture, style: Style) {
        let id = UUID()
        let audioName = "\(id.uuidString).m4a"
        let audioURL = folder.appending(path: audioName)
        processing = String(localized: "Saving the audio…")
        // Keep going for a while if the user leaves the app.
        let background = UIApplication.shared.beginBackgroundTask(withName: "Making a note")
        Task {
            defer { UIApplication.shared.endBackgroundTask(background) }
            let samples = capture.samples
            let savedAudio = await Task.detached(priority: .userInitiated) { () -> Bool in
                (try? AudioFileWriter.writeM4A(samples: samples, to: audioURL)) != nil
            }.value
            let result = await app.processLongForm(transcript: capture.transcript, style: style, language: capture.language) { [weak self] status in
                self?.processing = status
            }
            let note = Note(
                id: id,
                title: result.title ?? NoteRenderer.fallbackTitle(from: capture.transcript),
                styleID: style.id,
                status: .needsReview,
                recorded: capture.recorded,
                duration: capture.duration,
                device: "iphone",
                mode: .longForm,
                tags: result.knownTags,
                folder: folder(for: style),
                language: capture.language.code,
                body: result.body,
                transcript: keepsTranscript(style) ? capture.transcript : nil
            )
            let item = PendingNote(note: note, newTags: result.newTags, audioFile: savedAudio ? audioName : nil)
            pending.append(item)
            savePending()
            processing = nil
            reviewing = item
        }
    }

    /// Approve: status `reviewed`, with the title, tags and folder as edited. New tags join the vault's list.
    func approve(_ item: PendingNote, title: String, tags: [String], folder: String) {
        var note = item.note
        note.title = title.isEmpty ? note.title : title
        note.tags = tags
        note.folder = folder.isEmpty ? NoteFiling.defaultFolder : folder
        note.status = .reviewed
        let added = tags.filter { !app.tags.contains($0) }
        if !added.isEmpty { app.tags += added }
        finish(item, as: note)
    }

    /// Skip: filed as suggested with status `needs-review`, for the board.
    func skip(_ item: PendingNote) {
        finish(item, as: item.note)
    }

    /// Throw a note away before it's filed, audio included.
    func discard(_ item: PendingNote) {
        pending.removeAll { $0.id == item.id }
        savePending()
        if let audio = item.audioFile { try? FileManager.default.removeItem(at: folder.appending(path: audio)) }
        if reviewing?.id == item.id { reviewing = nil }
    }

    private func finish(_ item: PendingNote, as note: Note) {
        pending.removeAll { $0.id == item.id }
        savePending()
        reviewing = nil
        let audio = item.audioFile.map { folder.appending(path: $0) }
        let styleName = app.styles.first { $0.id == note.styleID }?.displayName ?? note.styleID
        Task {
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
    }

    func folder(for style: Style) -> String {
        guard let folder = style.folder?.trimmingCharacters(in: .whitespaces), !folder.isEmpty else { return NoteFiling.defaultFolder }
        return StoragePath.join(folder)
    }

    /// Rewritten notes keep the raw transcript under a Transcript heading; tidy and raw ones don't need it.
    private func keepsTranscript(_ style: Style) -> Bool {
        !style.isRaw && style.intensity != .light
    }

    private func savePending() {
        if let data = try? JSONEncoder().encode(pending) { try? data.write(to: folder.appending(path: "pending.json"), options: .atomic) }
    }

    private func saveRecent() {
        if let data = try? JSONEncoder().encode(recent) { try? data.write(to: folder.appending(path: "recent.json"), options: .atomic) }
    }
}
