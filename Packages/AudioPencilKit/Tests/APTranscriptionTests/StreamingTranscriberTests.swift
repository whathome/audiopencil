import APCore
import APTranscription
import Foundation
import Testing
import os

/// In-memory sample buffer the test grows by hand.
final class TestSource: SampleSource {
    private let storage = OSAllocatedUnfairLock<[Float]>(initialState: [])
    var count: Int { storage.withLock { $0.count } }
    func samples(from start: Int) -> [Float] { storage.withLock { Array($0[min(start, $0.count)...]) } }
    func append(seconds: Double, loud: Bool) {
        append(seconds: seconds, amplitude: loud ? 0.2 : 0)
    }
    func append(seconds: Double, amplitude: Float) {
        let chunk = (0..<Int(seconds * 16_000)).map { index in
            amplitude * sin(2 * .pi * 200 * Float(index) / 16_000)
        }
        storage.withLock { $0 += chunk }
    }
}

/// Pretends every 2 s of audio is one segment, named by its absolute start second,
/// so we can see which audio each pass covered.
actor FakeEngine: SpeechTranscribing {
    private let source: TestSource
    private(set) var calls: [Int] = [] // tail lengths in samples
    init(source: TestSource) { self.source = source }

    func transcribe(_ samples: [Float]) async throws -> [TranscriptSegment] {
        calls.append(samples.count)
        let offset = Double(source.count - samples.count) / 16_000
        let seconds = Double(samples.count) / 16_000
        return stride(from: 0.0, to: seconds, by: 2.0).map { start in
            TranscriptSegment(start: start, end: min(start + 2, seconds), text: "s\(Int(offset + start))")
        }
    }
}

struct StreamingTranscriberTests {
    @Test func confirmsEarlySegmentsAndLeavesShortTail() async throws {
        let source = TestSource()
        let engine = FakeEngine(source: source)
        let streamer = StreamingTranscriber(engine: engine, source: source)

        source.append(seconds: 10, loud: true)
        #expect(await streamer.passIfNeeded())
        // 5 segments, 2 held back: 0–6 s confirmed.
        source.append(seconds: 4, loud: true)
        #expect(await streamer.passIfNeeded())

        let text = try await streamer.finish()
        #expect(text == "s0 s2 s4 s6 s8 s10 s12")

        let calls = await engine.calls
        #expect(calls.count == 3)
        // The final pass only had the unconfirmed tail, not the whole 14 s.
        #expect(calls.last! < 14 * 16_000)
    }

    @Test func wholeRecordingAtStopReplacesLivePasses() async throws {
        let source = TestSource()
        let engine = FakeEngine(source: source)
        var configuration = StreamingTranscriber.Configuration()
        configuration.wholeRecordingAtStop = true
        let streamer = StreamingTranscriber(engine: engine, source: source, configuration: configuration)

        source.append(seconds: 10, loud: true)
        #expect(await streamer.passIfNeeded())
        source.append(seconds: 4, loud: true)

        let text = try await streamer.finish()
        #expect(text == "s0 s2 s4 s6 s8 s10 s12")
        // The last pass covered all 14 s, and nothing the live pass confirmed was counted twice.
        #expect(await engine.calls.last == 14 * 16_000)
    }

    @Test func skipsPassWithoutEnoughNewAudio() async {
        let source = TestSource()
        let engine = FakeEngine(source: source)
        let streamer = StreamingTranscriber(engine: engine, source: source)
        source.append(seconds: 0.5, loud: true)
        #expect(await streamer.passIfNeeded() == false)
        #expect(await engine.calls.isEmpty)
    }

    @Test func silenceIsNeverTranscribed() async throws {
        let source = TestSource()
        let engine = FakeEngine(source: source)
        let streamer = StreamingTranscriber(engine: engine, source: source)
        source.append(seconds: 5, loud: false)
        await streamer.passIfNeeded()
        let text = try await streamer.finish()
        #expect(text.isEmpty)
        #expect(await engine.calls.isEmpty)
    }

    @Test(arguments: [false, true])
    func quietMicrophoneReachesEngine(wholeRecordingAtStop: Bool) async throws {
        let source = TestSource()
        let engine = FakeEngine(source: source)
        var configuration = StreamingTranscriber.Configuration()
        configuration.wholeRecordingAtStop = wholeRecordingAtStop
        let streamer = StreamingTranscriber(engine: engine, source: source, configuration: configuration)
        // Quiet interface audio can have RMS well below the former 0.01 cutoff.
        source.append(seconds: 0.3, loud: false)
        source.append(seconds: 2, amplitude: 0.008)
        #expect(await streamer.passIfNeeded())
        #expect(await engine.calls.count == 1)
        #expect(try await streamer.finish() == "s0 s2")
        #expect(await engine.calls.count == 2)
    }

    @Test func quietShortHoldIsTranscribedAtStop() async throws {
        let source = TestSource()
        let engine = FakeEngine(source: source)
        let streamer = StreamingTranscriber(engine: engine, source: source)
        source.append(seconds: 0.5, amplitude: 0.008)
        #expect(await streamer.passIfNeeded() == false)
        #expect(try await streamer.finish() == "s0")
        #expect(await engine.calls == [8_000])
    }

    @Test func subThresholdNoiseIsNotTranscribed() async throws {
        let source = TestSource()
        let engine = FakeEngine(source: source)
        let streamer = StreamingTranscriber(engine: engine, source: source)
        source.append(seconds: 3, amplitude: 0.0005)
        await streamer.passIfNeeded()
        #expect(try await streamer.finish().isEmpty)
        #expect(await engine.calls.isEmpty)
    }
}

struct TranscriptCleanerTests {
    @Test func removesAnnotationsAndTidiesSpacing() {
        #expect(TranscriptCleaner.clean(" [BLANK_AUDIO]  Hello there , world. (music) *sigh*") == "Hello there, world.")
    }

    @Test func removesSoundTagsButKeepsRealParentheticals() {
        #expect(TranscriptCleaner.clean("(beep) Testing audio pencil.") == "Testing audio pencil.")
        #expect(TranscriptCleaner.clean("Meet at noon (Thursday) please.") == "Meet at noon (Thursday) please.")
    }

    @Test func punctuationAloneIsNotSpeech() {
        #expect(!TranscriptCleaner.hasSpeech(""))
        #expect(!TranscriptCleaner.hasSpeech("."))
        #expect(!TranscriptCleaner.hasSpeech(" - ... "))
        #expect(TranscriptCleaner.hasSpeech("OK."))
        #expect(TranscriptCleaner.hasSpeech("42"))
    }

    @Test func joinsSegments() {
        let segments = [
            TranscriptSegment(start: 0, end: 1, text: " First part."),
            TranscriptSegment(start: 1, end: 2, text: " Second part."),
        ]
        #expect(TranscriptCleaner.join(segments) == "First part. Second part.")
    }
}
