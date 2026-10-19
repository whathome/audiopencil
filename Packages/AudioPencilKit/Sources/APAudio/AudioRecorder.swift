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

/// Captures a microphone and converts it to 16 kHz mono Float32 for Whisper.
///
/// All engine work happens on a private serial queue, so starting the microphone (≈0.3 s of
/// Core Audio setup) never blocks the main thread. The engine can be warmed up before recording
/// begins (on the first Fn tap), so recording starts instantly on the second.
public final class AudioRecorder: @unchecked Sendable {
    public static let sampleRate: Double = 16_000

    public let samples = SampleStore()

    private let queue = DispatchQueue(label: "com.weshopkins.audiopencil.recorder", qos: .userInteractive)

    // Confined to `queue`.
    private var engine: AVAudioEngine?
    private var engineDevice: UInt32?
    private var engineRunning = false
    private var configurationObserver: (any NSObjectProtocol)?
    private var onInterruption: (@Sendable () -> Void)?
    private var recentRestarts: [Date] = []

    /// Shared with the audio thread.
    private struct TapState {
        var capturing = false
        var muteSamples = 0
        var onLevel: (@Sendable (Float) -> Void)?
    }
    private let tapState = OSAllocatedUnfairLock(initialState: TapState())

    public init() {}

    /// Starts the microphone without keeping any audio, so a recording can begin instantly.
    /// `deviceID` nil means the system default input.
    public func warmUp(deviceID: UInt32?) async throws {
        try await onQueue { try self.ensureRunning(deviceID: deviceID) }
    }

    /// Starts recording into `samples` (cleared first). Returns once audio is flowing.
    /// `onLevel` receives a 0…1 loudness value about every 100 ms, on the audio thread.
    /// If the input route changes mid-recording, capture restarts and keeps appending;
    /// `onInterruption` fires only if that restart fails.
    public func beginRecording(
        deviceID: UInt32?,
        onLevel: @escaping @Sendable (Float) -> Void,
        onInterruption: @escaping @Sendable () -> Void
    ) async throws {
        try await onQueue {
            try self.ensureRunning(deviceID: deviceID)
            self.onInterruption = onInterruption
            self.samples.removeAll()
            self.tapState.withLock {
                $0 = TapState(capturing: true, muteSamples: 0, onLevel: onLevel)
            }
        }
    }

    /// Replaces the next `seconds` of captured audio with silence (e.g. while the start cue plays).
    public func muteNext(seconds: Double) {
        tapState.withLock { $0.muteSamples = Int(seconds * Self.sampleRate) }
    }

    /// Stops capturing and turns the microphone off. Keeps the engine object for a faster next start.
    public func stop() {
        queue.sync {
            tapState.withLock { $0 = TapState() }
            onInterruption = nil
            guard let engine, engineRunning else { return }
            engine.stop()
            engineRunning = false
        }
    }

    private func onQueue(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: Queue-confined

    private func ensureRunning(deviceID: UInt32?) throws {
        if engineRunning, engineDevice == deviceID { return }
        let clock = ContinuousClock()
        let started = clock.now

        if engine == nil || engineDevice != deviceID {
            teardown()
            let engine = AVAudioEngine()
            try select(deviceID, on: engine)
            try installTap(on: engine)
            self.engine = engine
            self.engineDevice = deviceID
            observeConfigurationChanges(of: engine)
        }
        guard let engine else { return }
        engine.prepare()
        try engine.start()
        engineRunning = true
        Log.audio.notice("Microphone on in \(clock.now - started, privacy: .public)")
    }

    private func select(_ deviceID: UInt32?, on engine: AVAudioEngine) throws {
        #if os(macOS)
        guard var deviceID, let unit = engine.inputNode.audioUnit else { return }
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &deviceID, UInt32(MemoryLayout<UInt32>.size)
        )
        if status != noErr {
            Log.audio.error("Couldn't select input device \(deviceID): OSStatus \(status); using default")
        }
        #endif
    }

    private func installTap(on engine: AVAudioEngine) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.noInputDevice
        }
        let resampler = try Resampler(from: inputFormat)
        let store = samples
        let tapState = self.tapState
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            var chunk = resampler.convert(buffer)
            let count = chunk.count
            guard count > 0 else { return }
            let (capturing, mute, onLevel) = tapState.withLock { state in
                let mute = min(state.muteSamples, count)
                state.muteSamples -= mute
                return (state.capturing, mute, state.onLevel)
            }
            guard capturing else { return } // warmed up, not recording yet
            for index in 0..<mute { chunk[index] = 0 }
            store.append(chunk)
            onLevel?(Self.level(of: chunk))
        }
        Log.audio.info("Capturing input at \(inputFormat.sampleRate, privacy: .public) Hz, \(inputFormat.channelCount, privacy: .public) ch")
    }

    private func observeConfigurationChanges(of engine: AVAudioEngine) {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            queue.async { self.handleConfigurationChange() }
        }
    }

    /// The input route changed: a device was unplugged, AirPods switched profile, the sample rate changed,
    /// or (right after start) a non-default device finished taking over the input unit.
    /// Restart the same engine with a fresh tap. Rebuilding it instead re-triggers the change and loops.
    private func handleConfigurationChange() {
        guard let engine else { return }
        let now = Date()
        recentRestarts = recentRestarts.filter { now.timeIntervalSince($0) < 2 } + [now]
        let capturing = tapState.withLock { $0.capturing }
        guard recentRestarts.count <= 3 else {
            Log.audio.error("Audio route keeps changing; giving up on this engine")
            teardown()
            if capturing { onInterruption?() }
            return
        }
        Log.audio.notice("Audio route changed (\(capturing ? "recording" : "idle", privacy: .public)); restarting the input")
        do {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            try installTap(on: engine)
            if engineRunning {
                engine.prepare()
                try engine.start()
            }
        } catch {
            Log.audio.error("Couldn't restart capture: \(error.localizedDescription, privacy: .public)")
            teardown()
            if capturing { onInterruption?() }
        }
    }

    private func teardown() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        engineDevice = nil
        engineRunning = false
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
