@testable import APAudio
import Foundation
import Testing

struct MeetingEchoCancellerTests {
    @Test func delayedEchoAndRoomReflectionsAreRemoved() throws {
        let remote = signal(count: 16_000 * 12, seed: 12)
        let microphone = echo(of: remote)
        let clean = try process(remote: remote, microphone: microphone)
        #expect(clean.count == microphone.count)
        let start = 16_000 * 5
        let ratio = energy(clean[start...]) / energy(microphone[start...])
        #expect(ratio < 0.03, "Residual echo power: \(ratio)")
    }

    @Test func simultaneousLocalSpeechIsPreserved() throws {
        let remote = signal(count: 16_000 * 15, seed: 12)
        var local = signal(count: remote.count, seed: 67)
        for index in 0..<(16_000 * 7) { local[index] = 0 }
        let leakage = echo(of: remote)
        let microphone = zip(local, leakage).map(+)
        let clean = try process(remote: remote, microphone: microphone)
        let start = 16_000 * 9
        let difference = zip(clean[start...], local[start...]).map { $0 - $1 }
        let error = energy(difference[...]) / energy(local[start...])
        #expect(error < 0.25, "Double-talk distortion relative to local speech: \(error)")
        #expect(energy(clean[start...]) > energy(local[start...]) * 0.7)
    }

    @Test func delayedReferenceCallbacksAndUnequalChunksRemainAligned() throws {
        let remote = signal(count: 16_000 * 12, seed: 42)
        let microphone = echo(of: remote)
        let clean = try process(remote: remote, microphone: microphone, delayedReferenceFrames: 15, chunkSize: 937)
        #expect(clean.count == microphone.count)
        let start = 16_000 * 5
        let ratio = energy(clean[start...]) / energy(microphone[start...])
        #expect(ratio < 0.05, "Echo with delayed reference delivery: \(ratio)")
    }

    @Test func quietRemoteDoesNotMuteTheMicrophone() throws {
        let microphone = signal(count: 16_000 * 3 + 73, seed: 22)
        let clean = try process(remote: [Float](repeating: 0, count: microphone.count), microphone: microphone, chunkSize: 937)
        #expect(clean.count == microphone.count)
        #expect(energy(clean[16_000...]) > energy(microphone[16_000...]) * 0.8)
    }

    @Test func pauseFlushesTheTailAndResetsReferenceHistory() throws {
        let canceller = try MeetingEchoCanceller()
        let first = [Float](repeating: 0.1, count: 937)
        try canceller.appendReference(first, at: 0)
        #expect(try canceller.appendMicrophone(first, at: 0).isEmpty)
        let tail = try #require(canceller.finishAndReset().first)
        #expect(tail.start == 0)
        #expect(tail.samples.count == first.count)
        #expect(canceller.bufferedSampleCount == 0)
        _ = try canceller.appendMicrophone(first, at: 10)
        let resumed = try #require(canceller.finishAndReset().first)
        #expect(resumed.start == 10)
        #expect(resumed.samples.count == first.count)
    }

    @Test func invalidSamplesAreRejectedBeforePCMConversion() throws {
        let canceller = try MeetingEchoCanceller()
        #expect(throws: AudioRecorderError.self) { try canceller.appendMicrophone([.nan], at: 0) }
        #expect(throws: AudioRecorderError.self) { try canceller.appendReference([.infinity], at: 0) }
        #expect(throws: AudioRecorderError.self) { try canceller.appendMicrophone([0], at: .nan) }
        #expect(throws: AudioRecorderError.self) { try canceller.appendReference([Float](repeating: 0, count: 32_001), at: 0) }
    }

    @Test func stalledReferenceClockCannotGrowTheHistory() throws {
        let canceller = try MeetingEchoCanceller()
        for _ in 0..<300 { try canceller.appendReference([Float](repeating: 0, count: 160), at: 0) }
        #expect(canceller.bufferedSampleCount == 32_000)
    }

    private func process(remote: [Float], microphone: [Float], delayedReferenceFrames: Int = 0, chunkSize: Int = 160) throws -> [Float] {
        let canceller = try MeetingEchoCanceller()
        var output: [Float] = []
        var referenceOffset = 0
        for offset in stride(from: 0, to: microphone.count, by: chunkSize) {
            let referenceEnd = min(remote.count, max(0, offset + chunkSize - delayedReferenceFrames * 160))
            while referenceOffset < referenceEnd {
                let end = min(referenceEnd, referenceOffset + 320)
                try canceller.appendReference(Array(remote[referenceOffset..<end]), at: Double(referenceOffset) / 16_000)
                referenceOffset = end
            }
            let end = min(microphone.count, offset + chunkSize)
            let chunks = try canceller.appendMicrophone(Array(microphone[offset..<end]), at: Double(offset) / 16_000)
            for chunk in chunks { output.append(contentsOf: chunk.samples) }
            #expect(canceller.bufferedSampleCount <= 16_000 * 3)
        }
        while referenceOffset < remote.count {
            let end = min(remote.count, referenceOffset + 320)
            try canceller.appendReference(Array(remote[referenceOffset..<end]), at: Double(referenceOffset) / 16_000)
            referenceOffset = end
        }
        for chunk in canceller.finishAndReset() { output.append(contentsOf: chunk.samples) }
        return output
    }

    private func echo(of signal: [Float]) -> [Float] {
        signal.indices.map {
            ($0 >= 720 ? signal[$0 - 720] * 0.55 : 0) + ($0 >= 1_280 ? signal[$0 - 1_280] * 0.2 : 0)
        }
    }

    private func signal(count: Int, seed: UInt64) -> [Float] {
        var state = seed
        var previous: Float = 0
        return (0..<count).map { index in
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let noise = Float(Int32(truncatingIfNeeded: state >> 32)) / Float(Int32.max)
            previous = previous * 0.6 + noise * 0.4
            let envelope = 0.4 + 0.6 * abs(sin(Float(index) / 3_000))
            return previous * envelope * 0.45
        }
    }

    private func energy(_ samples: ArraySlice<Float>) -> Float {
        samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)
    }
}
