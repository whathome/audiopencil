@testable import APAudio
import AVFoundation
import Testing

struct ResamplerTests {
    @Test(arguments: [44_100.0, 48_000.0])
    func monoPreservesSignal(sampleRate: Double) throws {
        let input = try buffer(sampleRate: sampleRate, amplitudes: [0.12])
        let samples = try Resampler(from: input.format).convert(input)
        #expect(samples.count > 1_200) // The streaming converter retains its filter's initial latency.
        #expect(samples.count <= 1_600)
        #expect(abs(peak(samples) - 0.12) < 0.005)
    }

    #if os(macOS)
    @Test(arguments: [0, 1, 2, 3, 4, 5])
    func preservesEachDiscreteInterfaceInput(active: Int) throws {
        var amplitudes = [Float](repeating: 0, count: 6)
        amplitudes[active] = 0.12
        let input = try buffer(amplitudes: amplitudes)
        let samples = try Resampler(from: input.format).convert(input)
        #expect(samples.count > 1_200)
        #expect(abs(peak(samples) - 0.12) < 0.005)
    }

    @Test func oppositePhaseInputsDoNotCancel() throws {
        let input = try buffer(amplitudes: [0.12, -0.12])
        let samples = try Resampler(from: input.format).convert(input)
        #expect(abs(peak(samples) - 0.12) < 0.005)
    }

    @Test func followsActiveInputAcrossBuffers() throws {
        let first = try buffer(amplitudes: [0.12, 0, 0, 0, 0, 0])
        let second = try buffer(amplitudes: [0, 0.24, 0, 0, 0, 0])
        let resampler = try Resampler(from: first.format)
        #expect(abs(peak(resampler.convert(first)) - 0.12) < 0.005)
        #expect(abs(peak(resampler.convert(second)) - 0.24) < 0.005)
    }

    @Test func stereoMicrophonePreservesActiveChannel() throws {
        let input = try buffer(amplitudes: [0, 0.12], layoutTag: kAudioChannelLayoutTag_Stereo)
        let samples = try Resampler(from: input.format).convert(input)
        #expect(abs(peak(samples) - 0.12) < 0.005)
    }

    @Test func streamingPreservesDuration() throws {
        let input = try buffer(amplitudes: [0.12, 0, 0, 0, 0, 0])
        let resampler = try Resampler(from: input.format)
        let count = (0..<10).reduce(0) { total, _ in total + resampler.convert(input).count }
        #expect(count > 15_000)
        #expect(count <= 16_000)
    }
    #endif

    @Test func silenceStaysSilent() throws {
        let input = try buffer(amplitudes: [0])
        let samples = try Resampler(from: input.format).convert(input)
        #expect(!samples.isEmpty)
        #expect(peak(samples) == 0)
    }

    private func buffer(sampleRate: Double = 48_000, amplitudes: [Float], layoutTag: AudioChannelLayoutTag? = nil) throws -> AVAudioPCMBuffer {
        let layout = try #require(AVAudioChannelLayout(layoutTag: layoutTag ?? (kAudioChannelLayoutTag_DiscreteInOrder | UInt32(amplitudes.count))))
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, interleaved: false, channelLayout: layout)
        let frames = AVAudioFrameCount(sampleRate / 10)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channels = try #require(buffer.floatChannelData)
        for (channel, amplitude) in amplitudes.enumerated() {
            for frame in 0..<Int(frames) {
                channels[channel][frame] = amplitude * sin(Float(frame) * 2 * .pi * 440 / Float(sampleRate))
            }
        }
        return buffer
    }

    private func peak(_ samples: [Float]) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }
}
