import AVFoundation
import Foundation

/// Reads a saved recording back as 16 kHz mono samples (what Whisper and the speaker model take).
public enum AudioFileReader {
    /// Decodes imports in bounded buffers, preserving the source file and propagating decoder errors.
    public static func forEachMonoChunk(_ url: URL, consume: ([Float]) throws -> Void) throws {
        let file = try AVAudioFile(forReading: url)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: AudioRecorder.sampleRate, channels: 1),
              let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)
        else { throw CocoaError(.fileReadCorruptFile) }
        converter.downmix = true
        nonisolated(unsafe) var readError: (any Error)?
        while true {
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { requested, inputStatus in
                do {
                    guard file.framePosition < file.length else {
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    let capacity = min(requested, 8_192, AVAudioFrameCount(min(file.length - file.framePosition, 8_192)))
                    guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    try file.read(into: input, frameCount: capacity)
                    inputStatus.pointee = input.frameLength == 0 ? .endOfStream : .haveData
                    return input.frameLength == 0 ? nil : input
                } catch {
                    readError = error
                    inputStatus.pointee = .endOfStream
                    return nil
                }
            }
            if let readError { throw readError }
            if let conversionError { throw conversionError }
            if status == .error { throw CocoaError(.fileReadCorruptFile) }
            if output.frameLength > 0, let channel = output.floatChannelData?[0] {
                try consume(Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength))))
            }
            if status == .endOfStream { break }
        }
    }

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
