import Foundation

public struct TranscriptSegment: Sendable, Equatable {
    /// Seconds from the start of the audio that was passed in.
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Anything that turns 16 kHz mono samples into timed segments. `WhisperEngine` in the app;
/// a scripted fake in tests.
public protocol SpeechTranscribing: Sendable {
    func transcribe(_ samples: [Float]) async throws -> [TranscriptSegment]
}

public enum TranscriptCleaner {
    /// Joins segment texts and removes Whisper's non-speech annotations
    /// such as "[BLANK_AUDIO]", "(music)" or "*silence*".
    public static func join(_ segments: [TranscriptSegment]) -> String {
        clean(segments.map(\.text).joined(separator: " "))
    }

    public static func clean(_ text: String) -> String {
        var result = text
        for pattern in [#"\[[^\]]*\]"#, #"\([^)]*(music|silence|noise|inaudible|blank)[^)]*\)"#, #"\*[^*]*\*"#] {
            result = result.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #" ([,.;:!?])"#, with: "$1", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
