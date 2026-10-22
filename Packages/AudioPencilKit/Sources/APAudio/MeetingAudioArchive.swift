import AVFoundation
import APCore
import os

/// Disk-backed, bounded capture. Each closed CAF segment is committed to an atomic recovery index.
public final class MeetingAudioArchive: @unchecked Sendable {
    public enum Source: String, Codable, Sendable { case microphone, call, localVoice }

    public struct Segment: Codable, Sendable {
        public var source: Source
        public var start: Double
        public var frames: Int
        public var file: String
        public var end: Double { start + Double(frames) / AudioRecorder.sampleRate }
    }

    private struct State {
        var accepting = true
        var pausedAt: Double?
        var pausedDuration: Double = 0
        var pending = 0
    }
    private struct OpenSegment {
        var file: AVAudioFile
        var segment: Segment
    }

    public let directory: URL
    private let origin: Double
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "com.weshopkins.audiopencil.meeting-audio", qos: .userInitiated)
    private var open: [Source: OpenSegment] = [:]
    private var committed: [Segment] = []
    private var writesIndex = true
    private var failure: (any Error)?
    private let onFailure: @Sendable (String) -> Void
    private let echoCanceller: MeetingEchoCanceller?
    private let onMicrophoneLevel: (@Sendable (Float) -> Void)?
    private static let segmentFrames = 80_000

    public init(directory: URL, origin: Double = ProcessInfo.processInfo.systemUptime,
                echoCancellation: Bool = false,
                onMicrophoneLevel: (@Sendable (Float) -> Void)? = nil,
                onFailure: @escaping @Sendable (String) -> Void) throws {
        self.directory = directory
        self.origin = origin
        self.onFailure = onFailure
        self.echoCanceller = try echoCancellation ? MeetingEchoCanceller() : nil
        self.onMicrophoneLevel = onMicrophoneLevel
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func setPaused(_ paused: Bool, at time: Double = ProcessInfo.processInfo.systemUptime) {
        state.withLock {
            if paused, $0.pausedAt == nil { $0.pausedAt = time }
            if !paused, let start = $0.pausedAt {
                $0.pausedDuration += time - start
                $0.pausedAt = nil
            }
            queue.async { self.commitOpenSegments() }
        }
    }

    public func append(_ samples: [Float], source: Source, hostTime: Double) {
        state.withLock {
            guard $0.accepting, $0.pausedAt == nil else { return }
            $0.pending += 1
            let timestamp = max(0, hostTime - origin - $0.pausedDuration)
            queue.async {
                defer { self.state.withLock { $0.pending -= 1 } }
                guard self.failure == nil else { return }
                do {
                    guard self.state.withLock({ $0.pending <= 32 }) else {
                        throw AudioRecorderError.storageTooSlow
                    }
                    try self.write(samples, source: source, at: timestamp)
                    if let echoCanceller = self.echoCanceller {
                        switch source {
                        case .call: try echoCanceller.appendReference(samples, at: timestamp)
                        case .microphone: try self.writeVoice(echoCanceller.appendMicrophone(samples, at: timestamp))
                        case .localVoice: break
                        }
                    }
                } catch {
                    self.fail(error)
                }
            }
        }
    }

    public func finish() async throws -> [Segment] {
        return try await withCheckedThrowingContinuation { continuation in
            state.withLock {
                $0.accepting = false
                queue.async {
                    self.commitOpenSegments()
                    if let failure = self.failure { continuation.resume(throwing: failure) }
                    else { continuation.resume(returning: self.committed) }
                }
            }
        }
    }

    public static func segments(in directory: URL) throws -> [Segment] {
        let path = directory.appending(path: "audio.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        return try JSONDecoder().decode([Segment].self, from: Data(contentsOf: path))
    }

    private func write(_ samples: [Float], source: Source, at timestamp: Double) throws {
        var offset = 0
        while offset < samples.count {
            let start = timestamp + Double(offset) / AudioRecorder.sampleRate
            if let current = open[source], abs(current.segment.end - start) > 0.2 { try commit(source) }
            if open[source] == nil {
                let name = "\(source.rawValue)-\(UUID().uuidString).caf"
                let format = AVAudioFormat(standardFormatWithSampleRate: AudioRecorder.sampleRate, channels: 1)!
                let file = try AVAudioFile(forWriting: directory.appending(path: name), settings: format.settings)
                open[source] = OpenSegment(file: file, segment: Segment(source: source, start: start, frames: 0, file: name))
            }
            guard var current = open[source] else { throw CocoaError(.fileWriteUnknown) }
            let count = min(samples.count - offset, Self.segmentFrames - current.segment.frames)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: current.file.processingFormat, frameCapacity: AVAudioFrameCount(count)),
                  let channel = buffer.floatChannelData?[0] else { throw CocoaError(.fileWriteUnknown) }
            buffer.frameLength = AVAudioFrameCount(count)
            samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress! + offset, count: count) }
            try current.file.write(from: buffer)
            current.segment.frames += count
            open[source] = current
            offset += count
            if current.segment.frames >= Self.segmentFrames { try commit(source) }
        }
    }

    private func commit(_ source: Source) throws {
        guard let current = open.removeValue(forKey: source) else { return }
        let segment = current.segment
        current.file.close()
        committed.append(segment)
        if writesIndex {
            try JSONEncoder().encode(committed).write(to: directory.appending(path: "audio.json"), options: .atomic)
        }
    }

    private func commitOpenSegments() {
        do {
            if let echoCanceller { try writeVoice(echoCanceller.finishAndReset()) }
            for source in Array(open.keys) { try commit(source) }
        }
        catch { fail(error) }
    }

    private func writeVoice(_ chunks: [MeetingEchoCanceller.Chunk]) throws {
        for chunk in chunks {
            try write(chunk.samples, source: .localVoice, at: chunk.start)
            let rms = (chunk.samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(chunk.samples.count)).squareRoot()
            onMicrophoneLevel?(rms > 0 ? min(max((20 * log10(rms) + 60) / 60, 0), 1) : 0)
        }
    }

    public static func microphoneSource(in segments: [Segment]) -> Source {
        segments.contains { $0.source == .localVoice } ? .localVoice : .microphone
    }

    /// Restore a missing/incomplete cleaned track from raw sources without replacing the recovery index until complete.
    public static func recoverLocalVoice(directory: URL, segments: [Segment]) throws -> [Segment] {
        let microphones = segments.filter { $0.source == .microphone }
        let voices = segments.filter { $0.source == .localVoice }.sorted { $0.start < $1.start }
        let incomplete = microphones.contains { microphone in
            var covered = microphone.start
            for voice in voices where voice.end > covered {
                if voice.start > covered + 1 / AudioRecorder.sampleRate { return true }
                covered = voice.end
                if covered >= microphone.end - 1 / AudioRecorder.sampleRate { return false }
            }
            return true
        }
        guard incomplete else { return segments }
        let canceller = try MeetingEchoCanceller()
        let writer = try MeetingAudioArchive(directory: directory, origin: 0) { _ in }
        writer.writesIndex = false
        do {
            let end = segments.map(\.end).max() ?? 0
            var start: Double = 0
            while start < end {
                let duration = min(1, end - start)
                let reference = try read(directory: directory, segments: segments, source: .call, start: start, duration: duration)
                let microphone = try read(directory: directory, segments: segments, source: .microphone, start: start, duration: duration)
                try canceller.appendReference(reference, at: start)
                try writer.writeVoice(canceller.appendMicrophone(microphone, at: start))
                start += duration
            }
            try writer.writeVoice(canceller.finishAndReset())
            writer.commitOpenSegments()
            if let failure = writer.failure { throw failure }
            let updated = segments.filter { $0.source != .localVoice } + writer.committed
            try JSONEncoder().encode(updated).write(to: directory.appending(path: "audio.json"), options: .atomic)
            for voice in voices {
                let url = directory.appending(path: voice.file)
                guard url.lastPathComponent == voice.file, url.pathExtension == "caf" else { continue }
                do {
                    if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                        try FileManager.default.removeItem(at: url)
                    }
                } catch { Log.audio.error("Couldn't remove superseded voice audio: \(error.localizedDescription, privacy: .public)") }
            }
            return updated
        } catch {
            let created = writer.committed + writer.open.values.map(\.segment)
            for current in writer.open.values { current.file.close() }
            writer.open.removeAll()
            for segment in created {
                do { try FileManager.default.removeItem(at: directory.appending(path: segment.file)) }
                catch { Log.audio.error("Couldn't remove incomplete voice audio: \(error.localizedDescription, privacy: .public)") }
            }
            throw error
        }
    }

    private func fail(_ error: any Error) {
        guard failure == nil else { return }
        failure = error
        state.withLock { $0.accepting = false }
        Log.audio.error("Meeting audio write failed: \(error.localizedDescription, privacy: .public)")
        onFailure(error.localizedDescription)
    }

    /// Read only a bounded portion of a source, placing source gaps at their recorded offsets.
    public static func read(directory: URL, segments: [Segment], source: Source, start: Double, duration: Double) throws -> [Float] {
        let rate = AudioRecorder.sampleRate
        var samples = [Float](repeating: 0, count: max(0, Int((duration * rate).rounded())))
        for segment in segments where segment.source == source && segment.end > start && segment.start < start + duration {
            let first = max(start, segment.start)
            let last = min(start + duration, segment.end)
            let sourceOffset = max(0, Int(((first - segment.start) * rate).rounded()))
            let destinationOffset = max(0, Int(((first - start) * rate).rounded()))
            let count = min(Int(((last - first) * rate).rounded()), samples.count - destinationOffset, segment.frames - sourceOffset)
            guard count > 0 else { continue }
            let file = try AVAudioFile(forReading: directory.appending(path: segment.file))
            file.framePosition = AVAudioFramePosition(sourceOffset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)) else { throw CocoaError(.fileReadCorruptFile) }
            var copied = 0
            while copied < count {
                try file.read(into: buffer, frameCount: AVAudioFrameCount(count - copied))
                guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { throw CocoaError(.fileReadCorruptFile) }
                for frame in 0..<Int(buffer.frameLength) { samples[destinationOffset + copied + frame] = channel[frame] }
                copied += Int(buffer.frameLength)
            }
        }
        return samples
    }

    public static func export(directory: URL, segments: [Segment], to url: URL) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: AudioRecorder.sampleRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000]
        let output = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let end = segments.map(\.end).max() ?? 0
        let hasCall = segments.contains { $0.source == .call }
        var start: Double = 0
        while start < end {
            let duration = min(10, end - start)
            var samples = try read(directory: directory, segments: segments, source: microphoneSource(in: segments), start: start, duration: duration)
            guard !samples.isEmpty else { break }
            if hasCall {
                let call = try read(directory: directory, segments: segments, source: .call, start: start, duration: duration)
                for index in samples.indices { samples[index] = (samples[index] + call[index]) * 0.5 }
            }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { throw CocoaError(.fileWriteUnknown) }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
            try output.write(from: buffer)
            start += duration
        }
        output.close()
    }
}
