@testable import APPhonon
import FluidAudio
import Testing

struct PhononEngineTests {
    @Test func splitsIntoSentences() {
        let words = [("Quick", 0.0), ("update.", 0.4), ("Right", 1.0), ("now", 1.2), ("I", 1.4), ("back", 1.5), ("up?", 1.8), ("Yes", 2.5)]
            .map { WordTiming(word: $0.0, startTime: $0.1, endTime: $0.1 + 0.2) }
        let segments = PhononEngine.sentences(words)
        #expect(segments.map(\.text) == ["Quick update.", "Right now I back up?", "Yes"])
        #expect(segments[1].start == 1.0)
        #expect(segments[1].end == 2.0)
    }

    @Test func nothingHeardIsNoSegments() {
        #expect(PhononEngine.sentences([]).isEmpty)
    }
}
