import Foundation

/// Realistic raw transcripts: lowercase-ish, fillers, false starts, as Whisper produces them.
public enum BenchmarkFixtures {
    public static let lateReport = """
        Um, so hey Sarah, just wanted to let you know the, the quarterly report's going to be a day late. Uh, the \
        numbers from finance came in late yesterday, so I'll have it to you Thursday morning instead of Wednesday. \
        Uh, nothing else has changed. Let me know if that causes a problem with the board pack.
        """

    public static let diary = """
        Okay so today was, um, actually a pretty good day. I got up early, went for a run along the river, which I \
        haven't done in like two weeks, and it felt, it felt really good. Then work was, uh, mostly meetings, the \
        usual. The server migration finally finished though, so that's, that's a weight off. In the afternoon I \
        picked up the kids and we made pizza, and Maya put, like, way too much cheese on hers, which was funny. I'm \
        a bit tired now, but in a good way. I want to keep the running going, maybe three times a week. Yeah, that's \
        about it.
        """

    public static let workRamble = """
        So I've been thinking about the backup situation for the home server. Right now everything goes to, uh, the \
        external drive every night, and that's fine, but it's in the same room, so if there's a fire or whatever, \
        it's all gone. Um, options are, one, a second drive I keep at my parents' place and swap every month, two, \
        encrypted backups to the Nextcloud box at the cottage, or three, just pay for some cloud storage, which I \
        don't really want to do because the whole point is not depending on that. I'm leaning towards the cottage \
        because it's automatic, but the upload there is slow, like ten megabits, so the first sync would take, I \
        don't know, a week maybe. Um, I should test restoring too, I've never actually restored anything, which is \
        bad. So I'll set up the cottage sync this weekend, and I need to ask Dave if the router there can do a \
        static IP, and I'll do a test restore of the photos folder next week.
        """
}

extension BenchmarkFixtures {
    /// Spoken by `say` to test a transcription model; long enough to exercise streaming.
    public static let speechScript = """
        Audio Pencil is a private dictation app. It records your voice, transcribes it on this Mac, \
        and pastes the text into whatever you were typing in. Nothing is sent to the cloud. \
        The quick brown fox jumps over the lazy dog, and then the meeting moves to Thursday afternoon.
        """
}
