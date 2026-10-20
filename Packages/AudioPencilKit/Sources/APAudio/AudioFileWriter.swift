import AVFoundation

/// Saves a recording for the vault: AAC in an .m4a container, mono. About 1.2 MB for 5 minutes at 32 kbps.
public enum AudioFileWriter {
    public static func writeM4A(samples: [Float], sampleRate: Double = AudioRecorder.sampleRate, to url: URL, bitRate: Int = 32_000) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
        ]
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunkFrames = Int(sampleRate) * 10
        var offset = 0
        while offset < samples.count {
            let count = min(chunkFrames, samples.count - offset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)),
                  let channel = buffer.floatChannelData?[0]
            else { throw AudioRecorderError.unsupportedFormat("m4a") }
            buffer.frameLength = AVAudioFrameCount(count)
            samples.withUnsafeBufferPointer { source in
                channel.update(from: source.baseAddress! + offset, count: count)
            }
            try file.write(from: buffer)
            offset += count
        }
    }
}
