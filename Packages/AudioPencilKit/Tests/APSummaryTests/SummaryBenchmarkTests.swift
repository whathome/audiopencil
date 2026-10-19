import APCore
import APModels
import APSummary
import Foundation
import MLX
import Testing

/// Opt-in benchmark of candidate writing models on this Mac. Downloads each model (1.7–2.3 GB).
/// Run through xcodebuild (MLX needs its Metal shaders):
///
///   TEST_RUNNER_AUDIOPENCIL_BENCH=1 \
///   TEST_RUNNER_AUDIOPENCIL_BENCH_OUT=$PWD/docs/benchmarks/summary-models.md \
///   xcodebuild test -scheme AudioPencilKit-Package -destination platform=macOS -only-testing:APSummaryTests
///
/// AUDIOPENCIL_BENCH_MODELS (comma-separated repo IDs) overrides the candidate list.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AUDIOPENCIL_BENCH"] == "1"), .serialized)
struct SummaryBenchmarkTests {
    static let candidates = [
        "mlx-community/Qwen3-4B-4bit",
        "mlx-community/Llama-3.2-3B-Instruct-4bit",
        "mlx-community/SmolLM3-3B-4bit",
        "mlx-community/Qwen3.5-2B-4bit",
    ]

    struct Case {
        let name: String
        let transcript: String
        let style: Style
        let context: PromptBuilder.Context
    }

    static let cases: [Case] = [
        Case(name: "Quick note → Polished", transcript: Fixtures.lateReport, style: .polished, context: .quick),
        Case(name: "Quick note → Professional", transcript: Fixtures.lateReport, style: .professional, context: .quick),
        Case(name: "Diary → Diary", transcript: Fixtures.diary, style: .diary, context: .quick),
        Case(name: "Work ramble → Professional (long-form)", transcript: Fixtures.workRamble, style: .professional, context: .longForm),
    ]

    @Test func benchmarkCandidates() async throws {
        let environment = ProcessInfo.processInfo.environment
        let models = environment["AUDIOPENCIL_BENCH_MODELS"]?.split(separator: ",").map(String.init) ?? Self.candidates
        let outPath = environment["AUDIOPENCIL_BENCH_OUT"] ?? FileManager.default.temporaryDirectory.appending(path: "summary-benchmark.md").path
        let coordinator = ModelCoordinator()

        var report = """
            # Writing-model benchmark

            Machine: \(machine()), \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB, macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
            Run: \(Date().formatted(date: .abbreviated, time: .shortened)). Speeds are this run only; the first generation after a load includes MLX kernel compilation.

            """
        var summaryRows: [String] = []

        for modelID in models {
            print("[bench] \(modelID)")
            let engine = SummaryEngine(modelID: modelID)
            if !engine.isDownloaded {
                let started = ContinuousClock.now
                try await engine.download { _ in }
                print("[bench] downloaded in \(ContinuousClock.now - started)")
            }

            Memory.peakMemory = 0
            let loadStart = ContinuousClock.now
            try await coordinator.ensureLoaded(engine)
            let loadTime = ContinuousClock.now - loadStart
            let afterLoad = MemoryFootprint.currentBytes()

            report += "\n## \(modelID)\n\nLoad: \(seconds(loadTime)), footprint after load \(MemoryFootprint.formatted(afterLoad))\n"
            var totals: [Double] = []
            var genSpeeds: [Double] = []

            for testCase in Self.cases {
                let prompt = PromptBuilder.prompt(for: testCase.style, transcript: testCase.transcript, context: testCase.context)
                let started = ContinuousClock.now
                let output = try await engine.generate(instructions: prompt.instructions, input: prompt.input, maxTokens: prompt.maxTokens)
                let total = ContinuousClock.now - started
                totals.append(seconds(total).value)
                genSpeeds.append(output.generationTokensPerSecond)
                let cleaned = OutputCleaner.clean(output.text)
                print("[bench]   \(testCase.name): \(seconds(total)) total, \(Int(output.generationTokensPerSecond)) tok/s")
                report += """

                    ### \(testCase.name)

                    \(seconds(total)) total · prompt \(output.promptTokens) tokens at \(Int(output.promptTokensPerSecond)) tok/s · \
                    generated \(output.generatedTokens) tokens at \(Int(output.generationTokensPerSecond)) tok/s

                    \(cleaned.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n"))

                    """
            }

            let peakMLX = Memory.peakMemory
            await coordinator.unload(engine)
            let afterUnload = MemoryFootprint.currentBytes()
            report += "\nPeak MLX memory \(MemoryFootprint.formatted(UInt64(peakMLX))); footprint after unload \(MemoryFootprint.formatted(afterUnload))\n"
            summaryRows.append(
                "| \(modelID.replacingOccurrences(of: "mlx-community/", with: "")) | \(seconds(loadTime)) | "
                    + totals.map { String(format: "%.1f s", $0) }.joined(separator: " | ")
                    + " | \(Int(genSpeeds.reduce(0, +) / Double(genSpeeds.count))) | \(MemoryFootprint.formatted(UInt64(peakMLX))) |"
            )
        }

        let table = """

            ## Summary

            | Model | Load | \(Self.cases.map(\.name).joined(separator: " | ")) | Avg gen tok/s | Peak MLX memory |
            |---|---|\(String(repeating: "---|", count: Self.cases.count))---|---|
            \(summaryRows.joined(separator: "\n"))

            """
        report = report.replacingOccurrences(of: "\n## ", with: table + "\n## ", options: [], range: report.range(of: "\n## "))
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: outPath).deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.write(toFile: outPath, atomically: true, encoding: .utf8)
        print("[bench] report: \(outPath)")
    }

    private func seconds(_ duration: Duration) -> Measurement {
        Measurement(value: Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }

    private struct Measurement: CustomStringConvertible {
        let value: Double
        var description: String { String(format: "%.1f s", value) }
    }

    private func machine() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}

/// Realistic raw transcripts: lowercase-ish, fillers, false starts, as Whisper produces them.
enum Fixtures {
    static let lateReport = """
        Um, so hey Sarah, just wanted to let you know the, the quarterly report's going to be a day late. Uh, the \
        numbers from finance came in late yesterday, so I'll have it to you Thursday morning instead of Wednesday. \
        Uh, nothing else has changed. Let me know if that causes a problem with the board pack.
        """

    static let diary = """
        Okay so today was, um, actually a pretty good day. I got up early, went for a run along the river, which I \
        haven't done in like two weeks, and it felt, it felt really good. Then work was, uh, mostly meetings, the \
        usual. The server migration finally finished though, so that's, that's a weight off. In the afternoon I \
        picked up the kids and we made pizza, and Maya put, like, way too much cheese on hers, which was funny. I'm \
        a bit tired now, but in a good way. I want to keep the running going, maybe three times a week. Yeah, that's \
        about it.
        """

    static let workRamble = """
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
