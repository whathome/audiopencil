import AVFoundation
import Foundation

/// Reads a saved recording back as 16 kHz mono samples (what Whisper and the speaker model take).
public enum AudioFileReader {
    public static func readMono(_ url: URL, sampleRate: Double = AudioRecorder.sampleRate) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { throw CocoaError(.fileReadCorruptFile) }
        try file.read(into: input)
        let capacity = AVAudioFrameCount(Double(file.length) * sampleRate / file.processingFormat.sampleRate) + 4_096
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw CocoaError(.fileReadCorruptFile) }
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}
