import APCore
import APModels
@testable import APPhonon
import APTranscription
import AVFoundation
import Foundation
import Testing

/// Phonon-2 through the app's own path (`PhononEngine`, `StreamingTranscriber` with the whole recording
/// transcribed at stop), against Whisper Small (English) on the same audio. Opt-in: it downloads both
/// models (~0.8 GB) into the app's model folder, and Phonon-2's first load takes minutes:
///   AUDIOPENCIL_INTEGRATION=1 swift test --filter PhononIntegration
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AUDIOPENCIL_INTEGRATION"] == "1"), .serialized)
struct PhononIntegrationTests {
    static let script = """
        Quick update on the backup plan for the home server. Right now I back up the server every night to an \
        external drive in the same room, which is useless if there's a flood. This weekend I'm going to set up \
        encrypted backups to the cottage server. I need to ask Dave for a static IP before Saturday, and I'll \
        test a full restore on Sunday.
        """

    @Test func cleanAndRoomLikeSpeech() async throws {
        let clean = try Self.synthesise(Self.script)
        let room = Self.roomLike(clean)
        let coordinator = ModelCoordinator()
        let engines: [any DictationEngine] = [PhononEngine(), WhisperEngine(variant: "openai_whisper-small.en")]
        for engine in engines {
            if !engine.isDownloaded { try await engine.download { _ in } }
            let start = ContinuousClock.now
            try await coordinator.ensureLoaded(engine)
            print("[integration] \(engine.displayName) load: \(ContinuousClock.now - start)")
            for (name, samples) in [("clean", clean), ("room-like", room)] {
                let (text, stop) = try await Self.dictate(samples, with: engine)
                let wer = WordErrorRate.compute(reference: Self.script, hypothesis: text)
                print("[integration] \(engine.displayName) \(name): WER \(String(format: "%.1f", wer * 100))%, stop→text \(stop): \(text)")
                #expect(wer < 0.15, "\(engine.displayName) \(name)")
                // The end of the recording must survive the pass at stop.
                #expect(text.lowercased().contains("sunday"), "\(engine.displayName) \(name) lost the ending")
            }
        }
        for engine in engines { await coordinator.unload(engine) }
    }

    /// Half-second chunks with a pass after each, then stop, as the app does.
    static func dictate(_ samples: [Float], with engine: any DictationEngine) async throws -> (String, Duration) {
        let source = GrowingSource()
        var configuration = StreamingTranscriber.Configuration()
        configuration.wholeRecordingAtStop = engine.transcribesWholeRecordingAtStop
        let streamer = StreamingTranscriber(engine: engine, source: source, configuration: configuration)
        var index = 0
        while index < samples.count {
            source.append(Array(samples[index..<min(index + 8_000, samples.count)]))
            index += 8_000
            await streamer.passIfNeeded()
        }
        let start = ContinuousClock.now
        let text = try await streamer.finish()
        return (text, ContinuousClock.now - start)
    }

    /// Roughly a laptop microphone across a room: quieter, two echoes and a steady hiss.
    static func roomLike(_ samples: [Float]) -> [Float] {
        var seed: UInt64 = 42
        func noise() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int64(bitPattern: seed >> 11) % 2001 - 1000) / 1000
        }
        let first = 640, second = 1_920 // 40 ms and 120 ms at 16 kHz
        return samples.indices.map { i in
            var value = samples[i]
            if i >= first { value += 0.5 * samples[i - first] }
            if i >= second { value += 0.25 * samples[i - second] }
            return 0.15 * value + 0.003 * noise()
        }
    }

    static func synthesise(_ text: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appending(path: "audiopencil-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", "Samantha", "-o", url.path, "--file-format=WAVE", "--data-format=LEF32@16000", text]
        try process.run()
        process.waitUntilExit()
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}

final class GrowingSource: SampleSource, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Float] = []
    var count: Int { lock.withLock { storage.count } }
    func samples(from start: Int) -> [Float] { lock.withLock { Array(storage[min(start, storage.count)...]) } }
    func append(_ chunk: [Float]) { lock.withLock { storage += chunk } }
}
