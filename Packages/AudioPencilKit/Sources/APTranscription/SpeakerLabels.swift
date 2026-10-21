import Foundation

/// A word with its time in the recording, from Whisper.
public struct TimedWord: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Who was speaking when, from the speaker model. `speaker` is the model's own number for them.
public struct SpeakerSpan: Equatable, Sendable {
    public var speaker: Int
    public var start: Double
    public var end: Double

    public init(speaker: Int, start: Double, end: Double) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }
}

/// One speaker's turn: what they said until someone else spoke. Speakers are numbered 1, 2, 3… in the
/// order they first speak.
public struct SpeakerTurn: Equatable, Sendable {
    public var speaker: Int
    public var start: Double
    public var end: Double
    public var text: String
}

/// A meeting transcript: turns labelled Speaker 1, Speaker 2…
public struct SpeakerTranscript: Equatable, Sendable {
    public var turns: [SpeakerTurn]

    public init(turns: [SpeakerTurn]) {
        self.turns = turns
    }

    public var speakerCount: Int { Set(turns.map(\.speaker)).count }

    /// "Speaker", in the interface language, for labels in notes.
    public static var label: String { String(localized: "Speaker", bundle: .module) }

    /// "Speaker 1: …" paragraphs, for the writing model.
    public func text(label: String = SpeakerTranscript.label) -> String {
        turns.map { "\(label) \($0.speaker): \($0.text)" }.joined(separator: "\n\n")
    }

    /// "**Speaker 1:** …" paragraphs, for the note.
    public func markdown(label: String = SpeakerTranscript.label) -> String {
        turns.map { "**\(label) \($0.speaker):** \($0.text)" }.joined(separator: "\n\n")
    }

    /// Gives each word the speaker whose span overlaps it most (or the nearest span, for a word that
    /// falls in a gap), then joins runs of the same speaker into turns.
    public static func align(words: [TimedWord], spans: [SpeakerSpan]) -> SpeakerTranscript {
        guard !spans.isEmpty else {
            let text = cleaned(words.map(\.text))
            return SpeakerTranscript(turns: text.isEmpty ? [] : [SpeakerTurn(speaker: 1, start: words.first?.start ?? 0, end: words.last?.end ?? 0, text: text)])
        }
        // The model's numbers, renumbered by first appearance in the words.
        var numbers: [Int: Int] = [:]
        var turns: [SpeakerTurn] = []
        var current: (speaker: Int, start: Double, end: Double, words: [String])?
        func close() {
            guard let current else { return }
            let text = cleaned(current.words)
            if !text.isEmpty { turns.append(SpeakerTurn(speaker: current.speaker, start: current.start, end: current.end, text: text)) }
        }
        for word in words {
            let raw = speaker(for: word, in: spans)
            let speaker = numbers[raw] ?? {
                let next = numbers.count + 1
                numbers[raw] = next
                return next
            }()
            if current?.speaker == speaker {
                current?.end = word.end
                current?.words.append(word.text)
            } else {
                close()
                current = (speaker, word.start, word.end, [word.text])
            }
        }
        close()
        return SpeakerTranscript(turns: turns)
    }

    static func speaker(for word: TimedWord, in spans: [SpeakerSpan]) -> Int {
        var best: (speaker: Int, overlap: Double)?
        for span in spans {
            let overlap = min(word.end, span.end) - max(word.start, span.start)
            if overlap > 0, overlap > (best?.overlap ?? 0) { best = (span.speaker, overlap) }
        }
        if let best { return best.speaker }
        let middle = (word.start + word.end) / 2
        return spans.min { distance(middle, $0) < distance(middle, $1) }!.speaker
    }

    private static func distance(_ time: Double, _ span: SpeakerSpan) -> Double {
        time < span.start ? span.start - time : (time > span.end ? time - span.end : 0)
    }

    /// Drops Whisper's sound labels ("[BLANK_AUDIO]", "(beep)") from timed words, including labels split
    /// across several words ("[BL" + "ANK_AUDIO]"), and words with nothing spoken in them (a lone dash).
    public static func withoutSoundLabels(_ words: [TimedWord]) -> [TimedWord] {
        var closing: Character?
        return words.filter { word in
            let text = word.text.trimmingCharacters(in: .whitespaces)
            if let end = closing {
                if text.contains(end) { closing = nil }
                return false
            }
            if let open = text.first, open == "[" || open == "(" {
                let end: Character = open == "[" ? "]" : ")"
                // A bracketed label; "(" only counts when it's lowercase, as Whisper's sound tags are.
                if open == "[" || text.dropFirst().first?.isLowercase == true {
                    if !text.contains(end) { closing = end }
                    return false
                }
            }
            return TranscriptCleaner.hasSpeech(TranscriptCleaner.clean(word.text))
        }
    }

    /// Whisper's words carry their own leading spaces. Sound labels ("[BLANK_AUDIO]", "(beep)") arrive split
    /// across words, so they're cleaned from the joined turn, with the dash Whisper puts at a change of
    /// speaker. A turn with no words left is dropped.
    static func cleaned(_ words: [String]) -> String {
        var text = TranscriptCleaner.clean(words.joined())
        text = text.replacingOccurrences(of: #"(^|\s)[-–—]\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptCleaner.hasSpeech(text) ? text : ""
    }
}
