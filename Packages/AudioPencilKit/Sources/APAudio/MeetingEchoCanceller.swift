import CSpeexDSP
import Foundation

/// Confined to the archive queue. Raw sources stay on disk; only this derived signal is labelled "You".
final class MeetingEchoCanceller {
    struct Chunk {
        var samples: [Float]
        var start: Double
        var end: Double { start + Double(samples.count) / AudioRecorder.sampleRate }
    }

    private static let frameSize = 160
    private static let lookahead = 4_000
    private static let referenceLead = 0.05
    private static let referenceHistory = 2.0
    private let state: OpaquePointer
    private var references: [Chunk] = []
    private var pending: [Float] = []
    private var pendingStart: Double?
    private var microphoneFrame = [Int16](repeating: 0, count: MeetingEchoCanceller.frameSize)
    private var referenceFrame = [Int16](repeating: 0, count: MeetingEchoCanceller.frameSize)
    private var cancelledFrame = [Int16](repeating: 0, count: MeetingEchoCanceller.frameSize)

    var bufferedSampleCount: Int { pending.count + references.reduce(0) { $0 + $1.samples.count } }

    init() throws {
        guard let state = speex_echo_state_init(Int32(Self.frameSize), 8_192) else {
            throw AudioRecorderError.unsupportedFormat("could not create the meeting echo canceller")
        }
        var rate = Int32(AudioRecorder.sampleRate)
        guard speex_echo_ctl(state, SPEEX_ECHO_SET_SAMPLING_RATE, &rate) == 0 else {
            speex_echo_state_destroy(state)
            throw AudioRecorderError.unsupportedFormat("could not configure meeting echo cancellation")
        }
        self.state = state
    }

    deinit { speex_echo_state_destroy(state) }

    func appendReference(_ samples: [Float], at start: Double) throws {
        try validate(samples, at: start)
        guard !samples.isEmpty else { return }
        references.append(Chunk(samples: samples, start: start))
        let newestEnd = references.map(\.end).max() ?? start
        let cutoff = newestEnd - Self.referenceHistory
        references.removeAll { $0.end <= cutoff }
        for index in references.indices where references[index].start < cutoff {
            let trim = min(references[index].samples.count, Int(((cutoff - references[index].start) * AudioRecorder.sampleRate).rounded()))
            references[index].samples.removeFirst(trim)
            references[index].start += Double(trim) / AudioRecorder.sampleRate
        }
        var excess = references.reduce(0) { $0 + $1.samples.count } - 32_000
        while excess > 0, !references.isEmpty {
            let trim = min(excess, references[0].samples.count)
            if trim == references[0].samples.count { references.removeFirst() }
            else {
                references[0].samples.removeFirst(trim)
                references[0].start += Double(trim) / AudioRecorder.sampleRate
            }
            excess -= trim
        }
    }

    func appendMicrophone(_ samples: [Float], at start: Double) throws -> [Chunk] {
        try validate(samples, at: start)
        guard !samples.isEmpty else { return [] }
        var output: [Chunk] = []
        if let pendingStart, abs(start - pendingStart - Double(pending.count) / AudioRecorder.sampleRate) > 0.05 {
            if let tail = process(flush: true) { output.append(tail) }
            speex_echo_state_reset(state)
        }
        if pendingStart == nil { pendingStart = start }
        pending.append(contentsOf: samples)
        if let chunk = process(flush: false) { output.append(chunk) }
        return output
    }

    func finishAndReset() -> [Chunk] {
        let tail = process(flush: true)
        speex_echo_state_reset(state)
        references.removeAll(keepingCapacity: true)
        return tail.map { [$0] } ?? []
    }

    private func validate(_ samples: [Float], at start: Double) throws {
        guard start.isFinite, start >= 0, samples.count <= 32_000, samples.allSatisfy(\.isFinite) else {
            throw AudioRecorderError.unsupportedFormat("meeting echo cancellation requires finite 16 kHz buffers of at most two seconds")
        }
    }

    private func process(flush: Bool) -> Chunk? {
        guard let start = pendingStart else { return nil }
        let count = flush ? pending.count : max(0, pending.count - Self.lookahead) / Self.frameSize * Self.frameSize
        guard count > 0 else { return nil }
        var output = [Float]()
        output.reserveCapacity(count)
        for offset in stride(from: 0, to: count, by: Self.frameSize) {
            let length = min(Self.frameSize, count - offset)
            let time = start + Double(offset) / AudioRecorder.sampleRate
            // A small lead keeps the acoustic path causal despite different converter/callback latencies.
            let reference = referenceSamples(at: time + Self.referenceLead)
            for index in 0..<Self.frameSize {
                microphoneFrame[index] = index < length ? Self.pcm(pending[offset + index]) : 0
                referenceFrame[index] = Self.pcm(reference[index])
            }
            speex_echo_cancellation(state, &microphoneFrame, &referenceFrame, &cancelledFrame)
            output.append(contentsOf: cancelledFrame.prefix(length).map { Float($0) / 32_768 })
        }
        pending.removeFirst(count)
        pendingStart = pending.isEmpty ? nil : start + Double(count) / AudioRecorder.sampleRate
        return Chunk(samples: output, start: start)
    }

    private func referenceSamples(at start: Double) -> [Float] {
        let rate = AudioRecorder.sampleRate
        let end = start + Double(Self.frameSize) / rate
        var samples = [Float](repeating: 0, count: Self.frameSize)
        for chunk in references where chunk.end > start && chunk.start < end {
            let first = max(start, chunk.start)
            let source = max(0, Int(((first - chunk.start) * rate).rounded()))
            let destination = max(0, Int(((first - start) * rate).rounded()))
            let count = min(chunk.samples.count - source, Self.frameSize - destination,
                            Int(((min(end, chunk.end) - first) * rate).rounded()))
            if count > 0 {
                for index in 0..<count { samples[destination + index] = chunk.samples[source + index] }
            }
        }
        return samples
    }

    private static func pcm(_ sample: Float) -> Int16 {
        Int16((min(1, max(-1, sample)) * 32_767).rounded())
    }
}
