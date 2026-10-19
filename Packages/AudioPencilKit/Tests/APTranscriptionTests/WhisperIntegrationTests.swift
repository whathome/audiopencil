import APCore
import APModels
import APTranscription
import AVFoundation
import Foundation
import Testing

/// End-to-end check of WhisperKit + streaming on synthesised speech.
/// Opt-in because it downloads a model (~0.5 GB) into the app's model folder:
///   AUDIOPENCIL_INTEGRATION=1 swift test --filter WhisperIntegration
/// Set AUDIOPENCIL_MODEL to try another variant (default openai_whisper-small.en).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AUDIOPENCIL_INTEGRATION"] == "1"))
struct WhisperIntegrationTests {
    static let script = """
        Audio Pencil is a private dictation app. It records your voice, transcribes it on this Mac, \
        and pastes the text into whatever you were typing in. Nothing is sent to the cloud. \
        The quick brown fox jumps over the lazy dog, and then the meeting moves to Thursday afternoon.
        """

    @Test func streamsSynthesisedSpeech() async throws {
        let variant = ProcessInfo.processInfo.environment["AUDIOPENCIL_MODEL"] ?? "openai_whisper-small.en"
        let samples = try Self.synthesise(Self.script)
        let engine = WhisperEngine(variant: variant)
        if !engine.isDownloaded {
            try await engine.download { _ in }
        }
        let coordinator = ModelCoordinator()
        let loadStart = ContinuousClock.now
        try await coordinator.ensureLoaded(engine)
        print("[integration] load: \(ContinuousClock.now - loadStart), footprint \(MemoryFootprint.formatted(MemoryFootprint.currentBytes()))")

        // Feed audio in real time-sized chunks, running passes as the app would.
        let source = GrowingSource()
        let streamer = StreamingTranscriber(engine: engine, source: source)
        let chunk = 16_000 / 2
        var index = 0
        let streamStart = ContinuousClock.now
        while index < samples.count {
            source.append(Array(samples[index..<min(index + chunk, samples.count)]))
            index += chunk
            await streamer.passIfNeeded()
        }
        print("[integration] streaming passes took \(ContinuousClock.now - streamStart) for \(Double(samples.count) / 16_000)s of audio")

        let finishStart = ContinuousClock.now
        let text = try await streamer.finish()
        let finish = ContinuousClock.now - finishStart
        print("[integration] stop-to-text: \(finish); passes: \(await streamer.passCount); footprint \(MemoryFootprint.formatted(MemoryFootprint.currentBytes()))")
        print("[integration] text: \(text)")

        let lower = text.lowercased()
        for word in ["dictation", "transcribes", "cloud", "fox", "thursday"] {
            #expect(lower.contains(word), "missing \(word)")
        }
        await coordinator.unload(engine)
    }

    /// Uses the system `say` voice to make 16 kHz mono speech.
    static func synthesise(_ text: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appending(path: "audiopencil-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", url.path, "--file-format=WAVE", "--data-format=LEF32@16000", text]
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
