import APAudio
import AVFoundation
import Foundation
import Testing

struct RecordingStoreTests {
    private func store() throws -> RecordingStore {
        try RecordingStore(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    @Test func unclosedAudioIsRecoverableWithoutContainerFinalization() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let entry = try store.create(kind: .recorder, title: "Interrupted", language: "en", styleID: "raw")
        let writer = try RecordingWriter(id: entry.id, url: store.audioURL(for: entry.id))
        let first = (0..<16_000).map { Float($0 % 100) / 100 }
        try writer.append(first)
        try writer.append([0.75, -0.5])
        let reopened = try RecordingStore(root: store.root).load()
        #expect(reopened.errors.isEmpty)
        #expect(reopened.recordings.first?.status == .interrupted)
        #expect(try store.samples(for: entry.id) == first + [0.75, -0.5])
        #expect(reopened.recordings.first?.duration == Double(16_002) / 16_000)
        let playback = store.root.appending(path: "recovered.caf")
        try store.export(entry.id, to: playback)
        #expect(try AVAudioFile(forReading: playback).length == 16_002)
        try writer.finish()
    }

    @Test func partialSampleAtCrashDoesNotDestroyEarlierAudio() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let entry = try store.create(kind: .dictation, title: "Partial write", language: "fr", styleID: "raw")
        let writer = try RecordingWriter(id: entry.id, url: store.audioURL(for: entry.id))
        try writer.append([0.25, 0.5, 0.75])
        try writer.finish()
        let file = try FileHandle(forWritingTo: store.audioURL(for: entry.id))
        try file.seekToEnd()
        try file.write(contentsOf: Data([1, 2]))
        try file.close()
        #expect(try store.samples(for: entry.id) == [0.25, 0.5, 0.75])
        #expect(try store.duration(for: entry.id) == 3.0 / 16_000)
    }

    @Test func completionAndTranscriptSurviveRelaunchAndClosedWriterRejectsAudio() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.root) }
        var entry = try store.create(kind: .recorder, title: "Kept", language: "es", styleID: "raw")
        let writer = try RecordingWriter(id: entry.id, url: store.audioURL(for: entry.id))
        try writer.append([Float](repeating: 0.3, count: 16_000))
        try writer.finish()
        #expect(throws: RecordingStorageError.self) { try writer.append([0.9]) }
        entry.status = .ready
        entry.transcript = "Una idea."
        entry.body = "Una idea."
        entry.tags = ["idea"]
        entry.duration = try store.duration(for: entry.id)
        try store.save(entry)
        #expect(try store.load().recordings == [entry])
        let output = store.root.appending(path: "note.m4a")
        try store.export(entry.id, to: output, compressed: true)
        #expect(try AVAudioFile(forReading: output).length > 15_000)
        #expect(try store.samples(for: entry.id).count == 16_000)
    }

    @Test func corruptMetadataDoesNotHideHealthyRecordings() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.root) }
        var good = try store.create(kind: .recorder, title: "Good", language: "en", styleID: "raw")
        try RecordingWriter(id: good.id, url: store.audioURL(for: good.id)).finish()
        good.status = .ready
        try store.save(good)
        let broken = try store.create(kind: .recorder, title: "Broken", language: "en", styleID: "raw")
        try Data("invalid".utf8).write(to: store.directory(for: broken.id).appending(path: "session.json"))
        let snapshot = try store.load()
        #expect(snapshot.recordings == [good])
        #expect(snapshot.errors.count == 1)
    }

    @Test func missingAudioIsReportedRatherThanPresentedAsPlayable() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.root) }
        var entry = try store.create(kind: .recorder, title: "Missing audio", language: "en", styleID: "raw")
        entry.status = .ready
        entry.duration = 60
        try store.save(entry)
        let snapshot = try store.load()
        #expect(snapshot.recordings.isEmpty)
        #expect(snapshot.errors.count == 1)
    }

    @Test func openingAnotherWriterNeverTruncatesSavedAudio() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let entry = try store.create(kind: .recorder, title: "Kept", language: "en", styleID: "raw")
        let writer = try RecordingWriter(id: entry.id, url: store.audioURL(for: entry.id))
        try writer.append([0.1, 0.2])
        try writer.finish()
        #expect(throws: CocoaError.self) { try RecordingWriter(id: entry.id, url: store.audioURL(for: entry.id)) }
        #expect(try store.samples(for: entry.id) == [0.1, 0.2])
    }

    @Test func chunkedImportResamplesStereoAndRejectsUnreadableFiles() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let input = store.root.appending(path: "stereo.caf")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let file = try AVAudioFile(forWriting: input, settings: format.settings)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000))
        buffer.frameLength = 96_000
        for index in 0..<96_000 {
            buffer.floatChannelData![0][index] = 0.2
            buffer.floatChannelData![1][index] = 0.4
        }
        try file.write(from: buffer)
        file.close()
        var samples: [Float] = []
        try AudioFileReader.forEachMonoChunk(input) { chunk in
            #expect(chunk.count <= 16_000)
            samples += chunk
        }
        #expect(abs(samples.count - 32_000) < 100)
        #expect(samples.dropFirst(100).dropLast(100).allSatisfy { abs($0 - 0.3) < 0.01 })
        let corrupt = store.root.appending(path: "broken.mp3")
        try Data("not audio".utf8).write(to: corrupt)
        #expect(throws: (any Error).self) { try AudioFileReader.forEachMonoChunk(corrupt) { _ in } }
    }
}
