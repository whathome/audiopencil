import Testing

struct DictationIssueTests {
    @Test func microphonePermissionOpensPermissions() {
        let issue = DictationIssue.microphonePermission
        #expect(issue.recovery == .permissions)
        #expect(!issue.isNotice)
        #expect(!issue.message.isEmpty)
    }

    @Test func deviceFailureOpensMicrophoneSettings() {
        let issue = DictationIssue.microphone("Device disconnected")
        #expect(issue.recovery == .microphone)
        #expect(!issue.isNotice)
        #expect(issue.message.contains("Device disconnected"))
    }

    @Test func transcriptionFailureDoesNotOpenPermissions() {
        let issue = DictationIssue.transcription("Model unavailable")
        #expect(issue.recovery == .models)
        #expect(!issue.isNotice)
        #expect(issue.message.contains("Model unavailable"))
    }

    @Test func rewriteFallbackIsDismissibleAndPreservesTheReason() {
        let issue = DictationIssue.rewriteFallback("Not enough memory")
        #expect(issue.recovery == .dismiss)
        #expect(issue.isNotice)
        #expect(issue.message.contains("Not enough memory"))
    }
}
