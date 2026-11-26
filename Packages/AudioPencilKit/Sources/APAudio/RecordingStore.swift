import APCore
import AVFoundation
import Foundation
import os

public struct SavedRecording: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case dictation, recorder, imported }
    public enum Status: String, Codable, Sendable { case capturing, ready, interrupted }
    public var id: UUID
    public var title: String
    public var recorded: Date
    public var kind: Kind
    public var status: Status
    public var duration: Double
    public var language: String
    public var styleID: String
    public var transcript: String?
    public var body: String?
    public var notePath: String?
    public var tags: [String]?
}

public enum RecordingStorageError: LocalizedError {
    case closed, empty, corruptAudio

    public var errorDescription: String? {
        switch self {
        case .closed: String(localized: "The recording file is closed.", bundle: .module)
        case .empty: String(localized: "No audio was saved. Check the microphone or choose another audio file.", bundle: .module)
        case .corruptAudio: String(localized: "The saved audio could not be read. The original recording has been kept.", bundle: .module)
        }
    }
}

/// Headerless Float32 is the recovery source: no codec flush, container finalization, or periodic
/// index is needed to recover an application's interrupted write. Completed writes survive process exit.
public final class RecordingWriter: @unchecked Sendable {
    public let id: UUID
    private struct State {
        var file: FileHandle?
        var frames = 0
        var failure: (any Error)?
    }
    private let state: OSAllocatedUnfairLock<State>

    public init(id: UUID, url: URL) throws {
        self.id = id
        guard !FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileWriteFileExists) }
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        state = OSAllocatedUnfairLock(initialState: State(file: try FileHandle(forWritingTo: url)))
    }

    public var duration: Double { state.withLock { Double($0.frames) / AudioRecorder.sampleRate } }

    /// Writes before returning; capture never leaves accepted audio in a user-space dispatch backlog.
    /// This protects against app crashes, not hardware failure or audio that hasn't reached the callback.
    public func append(_ samples: [Float]) throws {
        try state.withLock { state in
            if let failure = state.failure { throw failure }
            guard let file = state.file else { throw RecordingStorageError.closed }
            do {
                try samples.withUnsafeBytes { try file.write(contentsOf: $0) }
                state.frames += samples.count
            } catch {
                state.failure = error
                throw error
            }
        }
    }

    public func finish() throws {
        try state.withLock { state in
            if let file = state.file {
                state.file = nil
                do {
                    try file.synchronize()
                    try file.close()
                } catch {
                    state.failure = error
                    try? file.close()
                }
            }
            if let failure = state.failure { throw failure }
        }
    }

    deinit {
        state.withLock { state in try? state.file?.close() }
    }
}

/// One local directory per recording. Metadata is atomic; the audio's file length is authoritative.
public struct RecordingStore: Sendable {
    public struct Snapshot: Sendable {
        public var recordings: [SavedRecording]
        public var errors: [String]
    }
    public let root: URL

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func directory(for id: UUID) -> URL { root.appending(path: id.uuidString, directoryHint: .isDirectory) }
    public func audioURL(for id: UUID) -> URL { directory(for: id).appending(path: "audio.f32") }

    public func create(kind: SavedRecording.Kind, title: String, language: String, styleID: String) throws -> SavedRecording {
        let recording = SavedRecording(id: UUID(), title: title, recorded: Date(), kind: kind,
                                       status: .capturing, duration: 0, language: language, styleID: styleID)
        try FileManager.default.createDirectory(at: directory(for: recording.id), withIntermediateDirectories: true)
        try save(recording)
        return recording
    }

    public func save(_ recording: SavedRecording) throws {
        try JSONEncoder().encode(recording).write(to: directory(for: recording.id).appending(path: "session.json"), options: .atomic)
    }

    public func load() throws -> Snapshot {
        var recordings: [SavedRecording] = []
        var errors: [String] = []
        for directory in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: directory.lastPathComponent) else { continue }
            do {
                var recording = try JSONDecoder().decode(SavedRecording.self, from: Data(contentsOf: directory.appending(path: "session.json")))
                guard recording.id == id else { throw CocoaError(.fileReadCorruptFile) }
                recording.duration = try duration(for: id)
                if recording.status == .capturing {
                    recording.status = .interrupted
                    try save(recording)
                }
                recordings.append(recording)
            } catch {
                errors.append("\(id.uuidString): \(error.localizedDescription)")
            }
        }
        return Snapshot(recordings: recordings.sorted { $0.recorded > $1.recorded }, errors: errors)
    }

    public func duration(for id: UUID) throws -> Double {
        let size = try FileManager.default.attributesOfItem(atPath: audioURL(for: id).path)[.size] as? NSNumber
        guard let size else { throw RecordingStorageError.corruptAudio }
        return Double(size.int64Value / 4) / AudioRecorder.sampleRate
    }

    public func samples(for id: UUID, from start: Int = 0, count: Int? = nil) throws -> [Float] {
        let file = try FileHandle(forReadingFrom: audioURL(for: id))
        defer { try? file.close() }
        try file.seek(toOffset: UInt64(max(0, start)) * 4)
        let data: Data
        if let count { data = try file.read(upToCount: max(0, count) * 4) ?? Data() }
        else { data = try file.readToEnd() ?? Data() }
        return data.withUnsafeBytes { bytes in
            (0..<(bytes.count / 4)).map { bytes.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self) }
        }
    }

    /// Generate a standard, playable copy in bounded chunks; the raw recovery source is never moved.
    public func export(_ id: UUID, to destination: URL, compressed: Bool = false) throws {
        let size = try FileManager.default.attributesOfItem(atPath: audioURL(for: id).path)[.size] as? NSNumber
        guard let size else { throw RecordingStorageError.corruptAudio }
        let frames = size.intValue / 4
        guard frames > 0 else { throw RecordingStorageError.empty }
        let temporary = destination.deletingLastPathComponent().appending(path: "\(UUID().uuidString).\(compressed ? "m4a" : "caf")")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let settings: [String: Any] = compressed ? [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: AudioRecorder.sampleRate,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000
        ] : AVAudioFormat(standardFormatWithSampleRate: AudioRecorder.sampleRate, channels: 1)!.settings
        let output = try AVAudioFile(forWriting: temporary, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        var offset = 0
        while offset < frames {
            let samples = try samples(for: id, from: offset, count: min(16_000, frames - offset))
            guard !samples.isEmpty,
                  let buffer = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { throw RecordingStorageError.corruptAudio }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
            try output.write(from: buffer)
            offset += samples.count
        }
        output.close()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
}
