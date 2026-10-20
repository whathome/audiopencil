import APAudio
import APCore
import APStorage
import Foundation
import Observation
import UIKit

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
        fileLeftoverReviews()
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

    /// Saves the audio, writes the note in `style`, then files it.
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
            // Suggested tags are used as they are; new ones join the vault's tag list.
            let added = result.newTags.filter { !app.tags.contains($0) }
            if !added.isEmpty { app.tags += added }
            let note = Note(
                id: id,
                title: result.title ?? NoteRenderer.fallbackTitle(from: capture.transcript),
                styleID: style.id,
                status: .needsReview,
                recorded: capture.recorded,
                duration: capture.duration,
                device: "iphone",
                mode: .longForm,
                tags: result.knownTags + added,
                folder: folder(for: style),
                language: capture.language.code,
                body: result.body,
                transcript: keepsTranscript(style) ? capture.transcript : nil
            )
            processing = String(localized: "Filing the note…")
            await file(note, audio: savedAudio ? audioURL : nil)
            processing = nil
        }
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
