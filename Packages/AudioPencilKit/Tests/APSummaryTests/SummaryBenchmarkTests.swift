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
        Case(name: "Quick note → Polished", transcript: BenchmarkFixtures.lateReport, style: .polished, context: .quick),
        Case(name: "Quick note → Professional", transcript: BenchmarkFixtures.lateReport, style: .professional, context: .quick),
        Case(name: "Diary → Diary", transcript: BenchmarkFixtures.diary, style: .diary, context: .quick),
        Case(name: "Work ramble → Professional (long-form)", transcript: BenchmarkFixtures.workRamble, style: .professional, context: .longForm),
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

