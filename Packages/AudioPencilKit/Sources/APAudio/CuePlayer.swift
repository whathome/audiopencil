import AVFoundation
import Foundation

/// Sounds for start, stop and cancel. Synthesised in memory (no bundled files), or the macOS system sounds.
public enum CueTheme: String, CaseIterable, Codable, Sendable {
    /// Warbling double chirp (the PRD's "tricorder").
    case tricorder
    /// Gentle rising and falling tones.
    case soft
    /// Bell-like two-note chime.
    case chime
    /// Short, quiet clicks.
    case click
    /// macOS's own Tink, Pop and Basso.
    case system
    case none

    public var label: String {
        switch self {
        case .tricorder: String(localized: "Tricorder", bundle: .module)
        case .soft: String(localized: "Soft", bundle: .module)
        case .chime: String(localized: "Chime", bundle: .module)
        case .click: String(localized: "Click", bundle: .module)
        case .system: String(localized: "macOS sounds", bundle: .module)
        case .none: String(localized: "None", bundle: .module)
        }
    }
}

@MainActor
public final class CuePlayer {
    public enum Cue: CaseIterable, Sendable {
        /// Recording started.
        case start
        /// Recording stopped.
        case stop
        /// Cancelled or failed.
        case cancel
        /// A recording just became long enough to be saved as a note.
        case mark
    }

    private var players: [Cue: AVAudioPlayer] = [:]
    public var volume: Float = 0.35
    public private(set) var theme: CueTheme = .tricorder

    public init(theme: CueTheme = .tricorder) {
        setTheme(theme)
    }

    public func setTheme(_ theme: CueTheme) {
        self.theme = theme
        players = [:]
        for cue in Cue.allCases {
            let player: AVAudioPlayer?
            switch theme {
            case .none:
                player = nil
            case .system:
                let name = switch cue { case .start: "Tink"; case .stop: "Pop"; case .cancel: "Basso"; case .mark: "Glass" }
                player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff"))
            default:
                player = try? AVAudioPlayer(data: ToneSynth.wav(for: cue, theme: theme))
            }
            player?.prepareToPlay()
            if let player { players[cue] = player }
        }
    }

    public func play(_ cue: Cue) {
        guard let player = players[cue] else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    /// Start then stop, for trying a theme in Settings.
    public func preview() {
        play(.start)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.play(.stop)
        }
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
        /// Bell-like: strike then fade, instead of a flat tone.
        var decays = false
        var harmonic: Double = 0.2
    }

    static func wav(for cue: CuePlayer.Cue, theme: CueTheme = .tricorder) -> Data {
        let parts: [(Chirp?, Double)] = parts(for: cue, theme: theme) // (chirp, or nil for silence of that duration)

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

    static func parts(for cue: CuePlayer.Cue, theme: CueTheme) -> [(Chirp?, Double)] {
        switch (theme, cue) {
        case (.soft, .start):
            [(Chirp(from: 660, to: 660, duration: 0.09, warbleDepth: 0, harmonic: 0), 0), (nil, 0.03), (Chirp(from: 880, to: 880, duration: 0.11, warbleDepth: 0, harmonic: 0), 0)]
        case (.soft, .stop):
            [(Chirp(from: 880, to: 660, duration: 0.12, warbleDepth: 0, harmonic: 0), 0)]
        case (.soft, .cancel):
            [(Chirp(from: 440, to: 330, duration: 0.16, warbleDepth: 0, harmonic: 0), 0)]
        case (.chime, .start):
            [(Chirp(from: 1046.5, to: 1046.5, duration: 0.22, warbleDepth: 0, decays: true, harmonic: 0.35), 0), (Chirp(from: 1318.5, to: 1318.5, duration: 0.32, warbleDepth: 0, decays: true, harmonic: 0.35), 0)]
        case (.chime, .stop):
            [(Chirp(from: 1318.5, to: 1318.5, duration: 0.18, warbleDepth: 0, decays: true, harmonic: 0.35), 0), (Chirp(from: 1046.5, to: 1046.5, duration: 0.3, warbleDepth: 0, decays: true, harmonic: 0.35), 0)]
        case (.chime, .cancel):
            [(Chirp(from: 523, to: 523, duration: 0.35, warbleDepth: 0, decays: true, harmonic: 0.35), 0)]
        case (.click, .start):
            [(Chirp(from: 2400, to: 2400, duration: 0.012, warbleDepth: 0, decays: true, harmonic: 0.5), 0), (nil, 0.06), (Chirp(from: 2800, to: 2800, duration: 0.012, warbleDepth: 0, decays: true, harmonic: 0.5), 0)]
        case (.click, .stop):
            [(Chirp(from: 2000, to: 2000, duration: 0.014, warbleDepth: 0, decays: true, harmonic: 0.5), 0)]
        case (.click, .cancel):
            [(Chirp(from: 700, to: 700, duration: 0.03, warbleDepth: 0, decays: true, harmonic: 0.5), 0)]
        case (_, .mark):
            // One quiet, low bell whatever the theme: noticeable, not alarming.
            [(Chirp(from: 784, to: 784, duration: 0.3, warbleDepth: 0, decays: true, harmonic: 0.3), 0)]
        case (_, .start):
            [(Chirp(from: 1900, to: 2500, duration: 0.055), 0), (nil, 0.045), (Chirp(from: 2300, to: 2900, duration: 0.055), 0)]
        case (_, .stop):
            [(Chirp(from: 2600, to: 1900, duration: 0.075), 0)]
        case (_, .cancel):
            [(Chirp(from: 900, to: 480, duration: 0.14, warbleHz: 40, warbleDepth: 60), 0)]
        }
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
            let attack = chirp.decays ? max(fade / 6, 1) : fade
            if index < attack { envelope = Double(index) / Double(attack) }
            if chirp.decays {
                envelope *= exp(-5 * progress) // strike, then ring down
            } else if index > count - fade {
                envelope = Double(count - index) / Double(fade)
            }
            // A touch of the octave makes it brighter without being harsh.
            let value = (sin(phase) * (1 - chirp.harmonic) + sin(phase * 2) * chirp.harmonic) * envelope
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
