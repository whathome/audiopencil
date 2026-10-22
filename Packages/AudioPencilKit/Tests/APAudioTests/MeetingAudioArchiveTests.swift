import APAudio
import AVFoundation
import Foundation
import Testing

struct MeetingAudioArchiveTests {
    @Test func independentSourcesAndGapsSurviveRecovery() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try MeetingAudioArchive(directory: directory, origin: 100) { _ in }
        archive.append([Float](repeating: 0.2, count: 16_000), source: .microphone, hostTime: 100)
        archive.append([Float](repeating: 0.4, count: 16_000), source: .call, hostTime: 101)
        _ = try await archive.finish()
        let segments = try MeetingAudioArchive.segments(in: directory)
        #expect(segments.count == 2)
        let mic = try MeetingAudioArchive.read(directory: directory, segments: segments, source: .microphone, start: 0, duration: 2)
        let call = try MeetingAudioArchive.read(directory: directory, segments: segments, source: .call, start: 0, duration: 2)
        #expect(mic.count == 32_000)
        #expect(mic[0] == 0.2)
        #expect(mic[16_000] == 0)
        #expect(call[0] == 0)
        #expect(call[16_000] == 0.4)
    }

    @Test func pauseRemovesTimeFromBothTracks() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try MeetingAudioArchive(directory: directory, origin: 100) { _ in }
        archive.append([Float](repeating: 0.2, count: 16_000), source: .microphone, hostTime: 100)
        archive.setPaused(true, at: 101)
        archive.append([Float](repeating: 0.9, count: 16_000), source: .call, hostTime: 105)
        archive.setPaused(false, at: 111)
        archive.append([Float](repeating: 0.3, count: 16_000), source: .call, hostTime: 111)
        let segments = try await archive.finish()
        #expect(segments.count == 2)
        #expect(segments.map(\.end).max() == 2)
        let callSegment = try #require(segments.first { $0.source == .call })
        let saved = try AVAudioFile(forReading: directory.appending(path: callSegment.file))
        #expect(saved.length == 16_000)
        let call = try MeetingAudioArchive.read(directory: directory, segments: segments, source: .call, start: 1, duration: 1)
        #expect(call.allSatisfy { abs($0 - 0.3) < 0.00001 }, "range \(call.min() ?? -1)...\(call.max() ?? -1), first \(call.first ?? -1), last \(call.last ?? -1), nonzero \(call.filter { $0 > 0.1 }.count), offset \(callSegment.start), file length \(saved.length)")
    }

    @Test func checkpointsAreAtMostFiveSecondsAndFinishedCaptureRejectsSamples() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try MeetingAudioArchive(directory: directory, origin: 100) { _ in }
        archive.append([Float](repeating: 0.1, count: 16_000 * 12), source: .microphone, hostTime: 100)
        let segments = try await archive.finish()
        #expect(segments.count == 3)
        #expect(segments.allSatisfy { $0.frames <= 80_000 })
        #expect(segments.map(\.frames).reduce(0, +) == 192_000)
        archive.append([1], source: .microphone, hostTime: 200)
        let finished = try await archive.finish()
        #expect(finished.count == segments.count)
        let slice = try MeetingAudioArchive.read(directory: directory, segments: segments, source: .microphone, start: 4.5, duration: 1)
        #expect(slice.count == 16_000)
        #expect(slice.allSatisfy { $0 == 0.1 })
    }

    @Test func finishingDrainsAcceptedBuffersBeforeReturning() async throws {
        for _ in 0..<8 {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let archive = try MeetingAudioArchive(directory: directory, origin: 100) { _ in }
            let producer = Task.detached {
                for index in 0..<16 {
                    archive.append([Float](repeating: 0.2, count: 80), source: .microphone, hostTime: 100 + Double(index) * 0.005)
                }
            }
            await Task.yield()
            let finished = try await archive.finish()
            await producer.value
            let drained = try await archive.finish()
            #expect(finished.map(\.file) == drained.map(\.file))
            #expect(finished.map(\.frames) == drained.map(\.frames))
        }
    }

    @Test func mixedPlaybackKeepsBothSourcesWithoutClipping() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try MeetingAudioArchive(directory: directory, origin: 100) { _ in }
        let mic = (0..<16_000).map { 0.7 * sin(Float($0) * 2 * .pi * 440 / 16_000) }
        let call = (0..<16_000).map { 0.7 * sin(Float($0) * 2 * .pi * 880 / 16_000) }
        archive.append(mic, source: .microphone, hostTime: 100)
        archive.append(call, source: .call, hostTime: 100)
        let segments = try await archive.finish()
        let output = directory.appending(path: "recording.m4a")
        try MeetingAudioArchive.export(directory: directory, segments: segments, to: output)
        let samples = try AudioFileReader.readMono(output)
        #expect(samples.count >= 15_000)
        #expect(samples.allSatisfy { abs($0) < 1 })
        let energy = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)
        #expect(energy > 0.08)
        #expect(energy < 0.16)
    }

    @Test(arguments: [false, true])
    func echoReducedVoiceSurvivesRecoveryAndFeedsPlayback(recoverExistingRaw: Bool) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try MeetingAudioArchive(directory: directory, origin: 100, echoCancellation: !recoverExistingRaw) { _ in }
        let remoteStep: Float = 2 * .pi * 400 / 16_000
        let localStep: Float = 2 * .pi * 2_300 / 16_000
        let remote: [Float] = (0..<128_000).map { 0.3 * sin(Float($0) * remoteStep) }
        let microphone: [Float] = remote.indices.map { index in
            let echo: Float = index >= 640 ? remote[index - 640] * 0.55 : 0
            let local: Float = index >= 80_000 ? 0.1 * sin(Float(index) * localStep) : 0
            return echo + local
        }
        for second in 0..<8 {
            let range = (second * 16_000)..<((second + 1) * 16_000)
            archive.append(Array(remote[range]), source: .call, hostTime: 100 + Double(second))
            archive.append(Array(microphone[range]), source: .microphone, hostTime: 100 + Double(second))
        }
        _ = try await archive.finish()
        let original = try MeetingAudioArchive.segments(in: directory)
        let segments = try MeetingAudioArchive.recoverLocalVoice(directory: directory, segments: original)
        let cached = try MeetingAudioArchive.recoverLocalVoice(directory: directory, segments: segments)
        #expect(cached.map(\.file) == segments.map(\.file))
        #expect(MeetingAudioArchive.microphoneSource(in: segments) == .localVoice)
        for source in [MeetingAudioArchive.Source.microphone, .call, .localVoice] {
            #expect(segments.filter { $0.source == source }.map(\.frames).reduce(0, +) == remote.count)
        }
        let raw = try MeetingAudioArchive.read(directory: directory, segments: segments, source: .microphone, start: 6, duration: 1)
        #expect(raw == Array(microphone[96_000..<112_000]))
        let output = directory.appending(path: "recording.m4a")
        try MeetingAudioArchive.export(directory: directory, segments: segments, to: output)
        let playback = try AudioFileReader.readMono(output)
        let tail = playback.suffix(16_000 * 2)
        let energy = tail.reduce(Float(0)) { $0 + $1 * $1 } / Float(tail.count)
        #expect(energy > 0.009)
        #expect(energy < 0.016, "Playback must use the echo-reduced microphone, not add the raw speaker leakage: \(energy)")
    }

    @Test func failedVoiceRecoveryPreservesTheOriginalIndex() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try MeetingAudioArchive(directory: directory, origin: 0) { _ in }
        let samples = [Float](repeating: 0.1, count: 16_000 * 8)
        archive.append(samples, source: .microphone, hostTime: 0)
        archive.append(samples, source: .call, hostTime: 0)
        let segments = try await archive.finish()
        let broken = try #require(segments.first { $0.source == .call && $0.start == 5 })
        try FileManager.default.removeItem(at: directory.appending(path: broken.file))
        let index = directory.appending(path: "audio.json")
        let original = try Data(contentsOf: index)
        #expect(throws: (any Error).self) {
            try MeetingAudioArchive.recoverLocalVoice(directory: directory, segments: segments)
        }
        #expect(try Data(contentsOf: index) == original)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(!files.contains { $0.hasPrefix("localVoice-") })
    }

    @Test func pauseFlushesEchoReducedAudioWithoutRetainingPausedSources() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try MeetingAudioArchive(directory: directory, origin: 100, echoCancellation: true) { _ in }
        archive.append([Float](repeating: 0.1, count: 937), source: .microphone, hostTime: 100)
        archive.setPaused(true, at: 100 + 937.0 / 16_000)
        archive.append([Float](repeating: 0.9, count: 16_000), source: .microphone, hostTime: 105)
        archive.append([Float](repeating: 0.9, count: 16_000), source: .call, hostTime: 105)
        archive.setPaused(false, at: 110 + 937.0 / 16_000)
        archive.append([Float](repeating: 0.2, count: 937), source: .microphone, hostTime: 110 + 937.0 / 16_000)
        let segments = try await archive.finish()
        let voice = segments.filter { $0.source == .localVoice }.sorted { $0.start < $1.start }
        #expect(voice.count == 2)
        #expect(voice.map(\.frames) == [937, 937])
        #expect(abs(voice[1].start - 937.0 / 16_000) < 0.00001)
        #expect(!segments.contains { $0.source == .call })
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "AudioPencilMeetingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
