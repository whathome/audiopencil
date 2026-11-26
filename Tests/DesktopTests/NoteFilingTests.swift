import APCore
import APSync
import Foundation
import Testing

@MainActor struct NoteFilingTests {
    @Test func missingAudioFailsBeforeQueuingAnAudioLessNote() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let outbox = Outbox(directory: root)
        let note = Note(title: "Kept recording", styleID: "raw", status: .needsReview,
                        recorded: Date(), duration: 10, mode: .longForm,
                        folder: "/Notes", body: "A thought.")
        await #expect(throws: (any Error).self) {
            try await NoteFiling.queue(note, audio: root.appending(path: "missing.m4a"), outbox: outbox, layout: .plain)
        }
        #expect(await outbox.pending.isEmpty)
    }

    @Test func filingQueuesBothAudioAndTextBeforeRemovingTheGeneratedCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let outbox = Outbox(directory: root.appending(path: "Outbox"))
        let audio = root.appending(path: "generated.m4a")
        try Data([1, 2, 3]).write(to: audio)
        let note = Note(title: "Kept recording", styleID: "raw", status: .needsReview,
                        recorded: Date(), duration: 10, mode: .longForm,
                        folder: "/Notes", body: "A thought.")
        let filed = try await NoteFiling.queue(note, audio: audio, outbox: outbox, layout: .plain)
        let pending = await outbox.pending
        #expect(pending.map(\.path) == [filed.note.audioPath, filed.path])
        #expect(!FileManager.default.fileExists(atPath: audio.path))
    }
}
