import APModels
import APTranscription
import Foundation
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["AUDIOPENCIL_DISCOVERY"] == "1"))
struct TranscriptionDiscoveryLiveTests {
    @Test func suggestsSupportedEnglishUpgrades() async throws {
        let machine = MachineProfile.current
        let found = try await TranscriptionModelDiscovery.suggestions(for: machine, current: "openai_whisper-small.en")
        print("[discovery] whisper budget \(ByteCountFormatter.string(fromByteCount: Int64(machine.transcriptionModelBudget), countStyle: .file))")
        for suggestion in found { print("[discovery]   \(suggestion.name) \(suggestion.sizeDescription)") }
        #expect(found.allSatisfy { $0.sizeBytes <= machine.transcriptionModelBudget })
    }
}
