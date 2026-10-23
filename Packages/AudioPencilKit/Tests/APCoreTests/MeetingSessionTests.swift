import APCore
import Foundation
import Testing

struct MeetingSessionTests {
    @Test(arguments: [MeetingSession.Stage.recording, .paused, .transcribing, .writing])
    func interruptedMeetingsRecoverWithoutLosingReview(_ stage: MeetingSession.Stage) {
        var meeting = MeetingSession(title: "Planning", kind: .inPerson, microphoneUID: "", microphoneName: "iPad", language: "en")
        meeting.stage = stage
        meeting.processingRequested = true
        meeting.turns = [.init(speaker: "Speaker 1", start: 1, end: 2, text: "Send the notes.")]
        meeting.actions = "- [ ] Alex: send the notes"
        meeting.speakerNames["Speaker 1"] = "Alex"
        meeting.recoverAfterInterruption(audioDuration: 23)
        #expect(meeting.stage == .saved)
        #expect(meeting.duration == 23)
        #expect(!meeting.processingRequested)
        #expect(meeting.warnings.count == 1)
        #expect(meeting.transcript == "Alex: Send the notes.")
        #expect(meeting.actions == "- [ ] Alex: send the notes")
        meeting.recoverAfterInterruption(audioDuration: 0)
        #expect(meeting.warnings.count == 1)
        #expect(meeting.duration == 23)
    }

    @Test func finishedMeetingsAreNotResetWhenReopened() {
        var meeting = MeetingSession(title: "Planning", kind: .inPerson, microphoneUID: "", microphoneName: "", language: "en")
        meeting.stage = .ready
        meeting.duration = 60
        meeting.reviewed = true
        meeting.recoverAfterInterruption(audioDuration: 0)
        #expect(meeting.stage == .ready)
        #expect(meeting.duration == 60)
        #expect(meeting.reviewed)
        #expect(meeting.warnings.isEmpty)
    }

    @Test func reviewAndSourceIdentityRoundTrip() throws {
        var meeting = MeetingSession(title: "Planning", kind: .videoCall, microphoneUID: "usb-interface", microphoneName: "Komplete Audio 6", language: "en")
        meeting.turns = [.init(speaker: "you", start: 1, end: 2, text: "I will send the notes.")]
        meeting.speakerNames["you"] = "Wes"
        meeting.actions = "- [ ] Wes: send notes"
        meeting.reviewed = true
        meeting.stage = .ready
        let decoded = try JSONDecoder().decode(MeetingSession.self, from: JSONEncoder().encode(meeting))
        #expect(decoded.microphoneUID == "usb-interface")
        #expect(decoded.transcript == "Wes: I will send the notes.")
        #expect(decoded.canonicalTranscript == "You: I will send the notes.")
        #expect(decoded.displayingSpeakerNames(in: "You: send the notes.") == "Wes: send the notes.")
        #expect(decoded.actions == meeting.actions)
        #expect(decoded.reviewed)
        #expect(decoded.stage == .ready)
    }

    @Test func renamingDoesNotChangeOtherSpeakerNumbersOrUnrelatedText() {
        var meeting = MeetingSession(title: "", kind: .inPerson, microphoneUID: "", microphoneName: "", language: "en")
        meeting.speakerNames["Speaker 1"] = "Alex $1"
        let rendered = meeting.displayingSpeakerNames(in: "Speaker 1 agreed. Speaker 10 disagreed. Speaker 11 listened.")
        #expect(rendered == "Alex $1 agreed. Speaker 10 disagreed. Speaker 11 listened.")
    }

    @Test func windowSpeakerNumbersAreMatchedByOverlapNotTheirOrdinal() {
        let previous: [MeetingSession.Turn] = [
            .init(speaker: "Speaker 1", start: 117, end: 119, text: "Yes."),
            .init(speaker: "Speaker 2", start: 119, end: 120, text: "Agreed.")
        ]
        let incoming: [MeetingSession.Turn] = [
            .init(speaker: "window-2", start: 117, end: 119, text: "Yes."),
            .init(speaker: "window-1", start: 119, end: 122, text: "Agreed."),
            .init(speaker: "window-3", start: 123, end: 126, text: "Next.")
        ]
        let mapping = MeetingSpeakerMatcher.mapping(incoming: incoming, previous: previous, before: 120)
        #expect(mapping["window-2"] == "Speaker 1")
        #expect(mapping["window-1"] == "Speaker 2")
        #expect(mapping["window-3"] == nil)
    }

    @Test func noOverlapDoesNotInventASpeakerMatch() {
        let incoming: [MeetingSession.Turn] = [.init(speaker: "window-1", start: 125, end: 127, text: "Hello.")]
        let previous: [MeetingSession.Turn] = [.init(speaker: "Speaker 1", start: 115, end: 116, text: "Bye.")]
        #expect(MeetingSpeakerMatcher.mapping(incoming: incoming, previous: previous, before: 120).isEmpty)
    }

    @Test func summarySectionsAreSeparatedWithoutLosingDecisions() throws {
        let result = try #require(MeetingSummaryParser.split("## Summary\nPlanning.\n\n## Decisions\nShip Friday.\n\n## Open questions\nNone.\n\n## Action items\n- [ ] Speaker 1: send notes"))
        #expect(result.summary.contains("Ship Friday."))
        #expect(!result.summary.contains("- [ ]"))
        #expect(result.actions == "- [ ] Speaker 1: send notes")
        #expect(MeetingSummaryParser.split("Invented unstructured output") == nil)
    }
}
