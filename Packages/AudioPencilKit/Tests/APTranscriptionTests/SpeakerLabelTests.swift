@testable import APTranscription
import Testing

struct SpeakerLabelTests {
    private func words(_ items: [(String, Double)]) -> [TimedWord] {
        items.map { TimedWord(text: " " + $0.0, start: $0.1, end: $0.1 + 0.4) }
    }

    @Test func wordsJoinIntoTurnsNumberedByFirstSpeaker() {
        // The model calls them 3 and 0; the note says Speaker 1 and Speaker 2, in speaking order.
        let spans = [SpeakerSpan(speaker: 3, start: 0, end: 2), SpeakerSpan(speaker: 0, start: 2.1, end: 4), SpeakerSpan(speaker: 3, start: 4.1, end: 6)]
        let transcript = SpeakerTranscript.align(
            words: words([("Shall", 0.1), ("we", 0.6), ("start?", 1.1), ("Yes,", 2.3), ("go", 2.9), ("ahead.", 3.4), ("Great.", 4.5)]),
            spans: spans
        )
        #expect(transcript.turns.map(\.speaker) == [1, 2, 1])
        #expect(transcript.speakerCount == 2)
        #expect(transcript.text(label: "Speaker") == "Speaker 1: Shall we start?\n\nSpeaker 2: Yes, go ahead.\n\nSpeaker 1: Great.")
        #expect(transcript.markdown(label: "Speaker").hasPrefix("**Speaker 1:** Shall we start?\n\n**Speaker 2:**"))
    }

    @Test func wordsInGapsGoToTheNearestSpeakerAndOverlapToTheLargerShare() {
        let spans = [SpeakerSpan(speaker: 0, start: 0, end: 1.0), SpeakerSpan(speaker: 1, start: 3.0, end: 4.0)]
        // 1.2 s is nearer the first span, 2.7 s nearer the second; 0.8–1.2 overlaps only the first.
        let transcript = SpeakerTranscript.align(words: words([("one", 0.1), ("two", 0.8), ("three", 1.2), ("four", 2.7), ("five", 3.2)]), spans: spans)
        #expect(transcript.turns.map(\.text) == ["one two three", "four five"])
    }

    @Test func noSpeakerSpansMeansOneSpeaker() {
        let transcript = SpeakerTranscript.align(words: words([("Just", 0), ("me.", 0.5)]), spans: [])
        #expect(transcript.turns.count == 1)
        #expect(transcript.turns.first?.text == "Just me.")
        #expect(SpeakerTranscript.align(words: [], spans: []).turns.isEmpty)
    }

    @Test func soundLabelsAndSpeakerDashesAreCleanedFromTurns() {
        let spans = [SpeakerSpan(speaker: 0, start: 0, end: 3), SpeakerSpan(speaker: 1, start: 3, end: 6)]
        let pieces: [(String, Double)] = [("[", 0.1), ("BLANK", 0.2), ("_AUDIO]", 0.3), ("-", 1.0), ("Good", 1.2), ("morning.", 1.6), ("(beep)", 3.1), ("- Hi", 3.5), ("there.", 4.0)]
        let transcript = SpeakerTranscript.align(words: pieces.map { TimedWord(text: " " + $0.0, start: $0.1, end: $0.1 + 0.2) }, spans: spans)
        #expect(transcript.turns.map(\.text) == ["Good morning.", "Hi there."])
        // A turn that was only a sound label disappears.
        let noise = SpeakerTranscript.align(words: [TimedWord(text: " (beep)", start: 0.5, end: 0.7)], spans: spans)
        #expect(noise.turns.isEmpty)
    }

    @Test func splitSoundLabelsAreDroppedFromTimedWords() {
        let raw = [" [BL", "ANK", "_AUDIO]", " That", " works", " (beep)", " (Laughs)", " -", " for", " me."]
        let words = raw.enumerated().map { TimedWord(text: $0.element, start: Double($0.offset), end: Double($0.offset) + 0.5) }
        // "(Laughs)" starts with a capital: kept, since speech can be in brackets.
        #expect(SpeakerTranscript.withoutSoundLabels(words).map(\.text) == [" That", " works", " (Laughs)", " for", " me."])
    }
}
