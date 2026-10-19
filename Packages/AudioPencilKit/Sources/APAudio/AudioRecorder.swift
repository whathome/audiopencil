import APCore
import AVFoundation
import os

/// Thread-safe, append-only store of 16 kHz mono samples for the current recording.
public final class SampleStore: SampleSource {
    private let storage = OSAllocatedUnfairLock<[Float]>(initialState: [])

    public init() {}

    public var count: Int { storage.withLock { $0.count } }

    public func append(_ chunk: [Float]) {
        storage.withLock { $0.append(contentsOf: chunk) }
    }

    /// Copies samples from `start` to the current end.
    public func samples(from start: Int) -> [Float] {
        storage.withLock { all in
            let lower = min(max(start, 0), all.count)
            return Array(all[lower...])
        }
    }

    public func removeAll() {
        storage.withLock { $0.removeAll(keepingCapacity: true) }
    }
}

public enum AudioRecorderError: LocalizedError {
    case noInputDevice
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .noInputDevice: "No microphone is available."
        case .unsupportedFormat(let format): "The microphone format isn't supported (\(format))."
        }
    }
}

/// Captures the default input device and converts it to 16 kHz mono Float32 for Whisper.
///
/// Milestone 2 adds the preferred-microphone priority list and device hot-plug handling.
public final class AudioRecorder: @unchecked Sendable {
    public static let sampleRate: Double = 16_000

    public let samples = SampleStore()

    // Touched only from the thread that calls start/stop (the main thread in the app).
    private var engine: AVAudioEngine?
    private var configurationObserver: (any NSObjectProtocol)?

    public init() {}

    public var isRunning: Bool { engine?.isRunning ?? false }

    /// Starts capturing. `onLevel` receives a 0…1 loudness value roughly every 100 ms, on the audio thread.
    /// If the input route changes mid-recording (e.g. AirPods switching profile), capture restarts on the
    /// new route and keeps appending; `onInterruption` fires only if that restart fails.
    /// Call start/stop from the main thread.
    public func start(
        onLevel: @escaping @Sendable (Float) -> Void,
        onInterruption: @escaping @Sendable () -> Void
    ) throws {
        stop()
        samples.removeAll()

        let engine = AVAudioEngine()
        try attachTap(to: engine, onLevel: onLevel)
        engine.prepare()
        try engine.start()
        self.engine = engine

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, let engine = self.engine else { return }
            Log.audio.notice("Audio route changed during recording; restarting capture")
            do {
                engine.inputNode.removeTap(onBus: 0)
                try self.attachTap(to: engine, onLevel: onLevel)
                engine.prepare()
                try engine.start()
            } catch {
                Log.audio.error("Couldn't restart capture: \(error.localizedDescription, privacy: .public)")
                onInterruption()
            }
        }
    }

    private func attachTap(to engine: AVAudioEngine, onLevel: @escaping @Sendable (Float) -> Void) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.noInputDevice
        }
        let resampler = try Resampler(from: inputFormat)
        let store = samples
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            let chunk = resampler.convert(buffer)
            guard !chunk.isEmpty else { return }
            store.append(chunk)
            onLevel(Self.level(of: chunk))
        }
        Log.audio.info("Capturing input at \(inputFormat.sampleRate, privacy: .public) Hz, \(inputFormat.channelCount, privacy: .public) ch")
    }

    public func stop() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    /// RMS loudness mapped from -60…0 dBFS to 0…1.
    static func level(of chunk: [Float]) -> Float {
        var sum: Float = 0
        for sample in chunk { sum += sample * sample }
        let rms = (sum / Float(chunk.count)).squareRoot()
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(max((decibels + 60) / 60, 0), 1)
    }
}

/// Streaming sample-rate and channel conversion to 16 kHz mono. Used only on the audio tap thread.
private final class Resampler: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let ratio: Double

    init(from inputFormat: AVAudioFormat) throws {
        guard
            let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioRecorder.sampleRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else {
            throw AudioRecorderError.unsupportedFormat(inputFormat.description)
        }
        converter.downmix = true
        self.converter = converter
        self.outputFormat = outputFormat
        self.ratio = AudioRecorder.sampleRate / inputFormat.sampleRate
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return [] }

        // The input block runs synchronously inside convert(); it just hands over this one buffer.
        nonisolated(unsafe) let input = buffer
        let supplied = OneShotFlag()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied.isSet {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied.isSet = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, let channel = output.floatChannelData?[0] else {
            Log.audio.error("Conversion failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            return []
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}

private final class OneShotFlag: @unchecked Sendable {
    var isSet = false
}
