import APCore
import Foundation
import Testing

struct WritingSampleTests {
    private let diary = WritingSample(id: "d", kind: "diary", text: "Today was slow. I felt tired after the run but the kids made pizza and that lifted the evening. Tomorrow I want to sleep earlier.")
    private let email = WritingSample(id: "e", kind: "work-email", text: "Hi Sam, quick update: the report will be a day late because finance sent the numbers late. You'll have it Thursday morning. Shout if that's a problem.")
    private let recap = WritingSample(id: "r", kind: "recap", text: "Quick recap of the planning meeting: we agreed to move the launch to March, Priya owns the budget, and Tom is booking the venue.")

    @Test func interviewHasTheElevenPRDPrompts() {
        #expect(InterviewPrompt.all.count == 11)
        #expect(Set(InterviewPrompt.all.map(\.id)).count == 11)
        #expect(InterviewPrompt.wordRange == 100...300)
    }

    @Test func picksTheClosestSamples() {
        let samples = [diary, email, recap]
        #expect(WritingSampleSelector.pick(for: "today I felt good after a run, the kids were funny", from: samples, limit: 1).map(\.id) == ["d"])
        #expect(WritingSampleSelector.pick(for: "tell the client the report is late, finance numbers came in late", from: samples, limit: 1).map(\.id) == ["e"])
        #expect(WritingSampleSelector.pick(for: "notes from the meeting, we agreed and decided on the venue", from: samples, limit: 1).map(\.id) == ["r"])
    }

    @Test func respectsTheWordBudgetAndAlwaysGivesSomething() {
        let long = WritingSample(id: "l", kind: "opinion", text: String(repeating: "word ", count: 800))
        let picked = WritingSampleSelector.pick(for: "anything", from: [long], wordBudget: 450)
        #expect(picked.count == 1)
        #expect(picked[0].wordCount == 450)
        #expect(WritingSampleSelector.pick(for: "x", from: []).isEmpty)
    }

    @Test func likeMePromptCarriesExamples() {
        var style = Style.likeMe
        style.isEnabled = true
        let prompt = PromptBuilder.prompt(for: style, transcript: "hello", context: .quick, vocabulary: [], examples: [email])
        #expect(prompt.instructions.contains("<example kind=\"work-email\">"))
        #expect(prompt.instructions.contains("Don't copy their content."))
    }
}

struct WordErrorRateTests {
    @Test func countsEditsIgnoringCaseAndPunctuation() {
        #expect(WordErrorRate.compute(reference: "The quick brown fox.", hypothesis: "the quick brown fox") == 0)
        #expect(WordErrorRate.compute(reference: "the quick brown fox", hypothesis: "the quick fox") == 0.25)
        #expect(WordErrorRate.compute(reference: "next cloud", hypothesis: "Nextcloud") == 1)
    }
}
