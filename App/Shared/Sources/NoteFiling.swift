import APCore
import APStorage
import APSync
import Foundation

/// A long-form note waiting for review. Kept on this device (with its audio) until approved or skipped.
struct PendingNote: Codable, Identifiable, Equatable {
    var note: Note
    /// Suggested tags that aren't in the vault's tag list yet.
    var newTags: [String]
    /// Audio file name in the pending folder.
    var audioFile: String?
    var id: UUID { note.id }
}

/// A note handed to the upload queue, for the Notes page.
struct RecentNote: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var styleName: String
    var recorded: Date
    var path: String
    var status: Note.Status
    /// Set from the Notes page: kept forever (archive) or on its way out (delete).
    var retention: Note.Retention?
    /// The written text, for copying when the vault can't be reached (older entries don't have it).
    var body: String?
}

/// Where notes and recordings go in the vault, and handing them to the upload queue.
enum NoteFiling {
    static let defaultFolder = "/Audio Pencil/Notes"
    static let recordingsFolder = "/Audio Pencil/Recordings"

    /// Queues the note's audio (if any, which is then removed from this device) and its Markdown.
    /// Returns the note as filed, with its audio path set, and the note's path.
    @discardableResult
    static func queue(_ note: Note, audio: URL?, outbox: Outbox, layout: NoteLayout) async throws -> (note: Note, path: String) {
        var note = note
        let base = NoteRenderer.baseName(for: note)
        if let audio, let data = try? Data(contentsOf: audio) {
            let path = StoragePath.join(recordingsFolder, base + ".m4a")
            note.audioPath = path
            try await outbox.enqueue(path: path, data: data)
            try? FileManager.default.removeItem(at: audio)
        }
        let path = NoteRenderer.notePath(for: note)
        try await outbox.enqueue(path: path, data: Data(NoteRenderer.markdown(for: note, layout: layout).utf8))
        return (note, path)
    }
}
