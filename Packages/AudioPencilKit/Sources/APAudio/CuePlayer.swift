import AVFoundation
import Foundation

/// Short synthesised "tricorder" cues. Generated in memory, so there are no bundled sound files.
@MainActor
public final class CuePlayer {
    public enum Cue: CaseIterable, Sendable {
        /// Double chirp: recording started.
        case start
        /// Single chirp: recording stopped.
        case stop
        /// Low falling blip: cancelled or failed.
        case cancel
    }

    private var players: [Cue: AVAudioPlayer] = [:]
    public var volume: Float = 0.35

    public init() {
        for cue in Cue.allCases {
            let data = ToneSynth.wav(for: cue)
            if let player = try? AVAudioPlayer(data: data) {
                player.prepareToPlay()
                players[cue] = player
            }
        }
    }

    public func play(_ cue: Cue) {
        guard let player = players[cue] else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }
}

enum ToneSynth {
    static let sampleRate = 44_100.0

    struct Chirp {
        var from: Double
        var to: Double
        var duration: Double
        /// Fast frequency wobble gives the "tricorder" texture.
        var warbleHz: Double = 70
        var warbleDepth: Double = 160
    }

    static func wav(for cue: CuePlayer.Cue) -> Data {
        let parts: [(Chirp?, Double)] // (chirp, or nil for silence of that duration)
        switch cue {
        case .start:
            parts = [
                (Chirp(from: 1900, to: 2500, duration: 0.055), 0),
                (nil, 0.045),
                (Chirp(from: 2300, to: 2900, duration: 0.055), 0),
            ]
        case .stop:
            parts = [(Chirp(from: 2600, to: 1900, duration: 0.075), 0)]
        case .cancel:
            parts = [(Chirp(from: 900, to: 480, duration: 0.14, warbleHz: 40, warbleDepth: 60), 0)]
        }

        var samples: [Float] = []
        for (chirp, silence) in parts {
            if let chirp {
                samples += render(chirp)
            } else {
                samples += [Float](repeating: 0, count: Int(silence * sampleRate))
            }
        }
        return encodeWAV(samples)
    }

    static func render(_ chirp: Chirp) -> [Float] {
        let count = Int(chirp.duration * sampleRate)
        let fade = Int(0.006 * sampleRate)
        var phase = 0.0
        var output = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / sampleRate
            let progress = Double(index) / Double(count)
            let base = chirp.from + (chirp.to - chirp.from) * progress
            let frequency = base + chirp.warbleDepth * sin(2 * .pi * chirp.warbleHz * t)
            phase += 2 * .pi * frequency / sampleRate
            var envelope = 1.0
            if index < fade { envelope = Double(index) / Double(fade) }
            if index > count - fade { envelope = Double(count - index) / Double(fade) }
            // A touch of the octave makes it brighter without being harsh.
            let value = (sin(phase) * 0.8 + sin(phase * 2) * 0.2) * envelope
            output[index] = Float(value)
        }
        return output
    }

    static func encodeWAV(_ samples: [Float]) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            let clipped = max(-1, min(1, sample))
            var value = Int16(clipped * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))           // chunk size
        append(UInt16(1))            // PCM
        append(UInt16(1))            // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))            // block align
        append(UInt16(16))           // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}
