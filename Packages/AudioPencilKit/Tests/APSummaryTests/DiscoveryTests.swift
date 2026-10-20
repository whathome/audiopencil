import APModels
import APSummary
import Foundation
import Testing

/// Opt-in: queries Hugging Face. TEST_RUNNER_AUDIOPENCIL_DISCOVERY=1 xcodebuild test … -only-testing:APSummaryTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AUDIOPENCIL_DISCOVERY"] == "1"))
struct WritingDiscoveryLiveTests {
    @Test func findsModelsThatFitThisMac() async throws {
        let machine = MachineProfile.current
        let known = Set(WritingModelOption.catalogue.map(\.id))
        let found = try await WritingModelDiscovery.suggestions(for: machine, excluding: known)
        print("[discovery] \(machine.summary), writing budget \(ByteCountFormatter.string(fromByteCount: Int64(machine.writingModelBudget), countStyle: .file))")
        for suggestion in found { print("[discovery]   \(suggestion.name) \(suggestion.sizeDescription) · \(suggestion.reason)") }
        #expect(found.allSatisfy { $0.sizeBytes <= machine.writingModelBudget && !known.contains($0.id) })

        // A 64 GB machine gets a bigger budget and at least as many options.
        var big = machine
        big.physicalMemory = 64 * 1_073_741_824
        let bigger = try await WritingModelDiscovery.suggestions(for: big, excluding: known)
        print("[discovery] 64 GB would get: \(bigger.map { "\($0.name) \($0.sizeDescription)" }.joined(separator: "; "))")
        #expect(bigger.contains { $0.sizeBytes > machine.writingModelBudget })
    }
}
