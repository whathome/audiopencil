import APCore
import APModels
import APSummary
import Darwin
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
/// AUDIOPENCIL_BENCH_MODELS (comma-separated repo IDs) overrides the candidate list. Run one model per invocation
/// when comparing peak process footprint: it is the process lifetime peak.
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
        let prompt: StylePrompt
    }

    static let cases: [Case] = [
        Case(name: "Quick note → Polished", prompt: PromptBuilder.prompt(for: .polished, transcript: BenchmarkFixtures.lateReport, context: .quick)),
        Case(name: "Quick note → Professional", prompt: PromptBuilder.prompt(for: .professional, transcript: BenchmarkFixtures.lateReport, context: .quick)),
        Case(name: "Diary → Diary", prompt: PromptBuilder.prompt(for: .diary, transcript: BenchmarkFixtures.diary, context: .quick)),
        Case(name: "Work ramble → Professional (long-form)", prompt: PromptBuilder.prompt(for: .professional, transcript: BenchmarkFixtures.workRamble, context: .longForm)),
        // The first pass of a long recording: per-section notes, combined afterwards.
        Case(name: "Work ramble → section notes", prompt: PromptBuilder.sectionNotesPrompt(section: BenchmarkFixtures.workRamble, index: 1, count: 2, vocabulary: [])),
    ]

    /// Time from the start of `generate` to the first streamed text.
    private final class FirstToken: @unchecked Sendable {
        private let lock = NSLock()
        private let started = ContinuousClock.now
        private var elapsed: Duration?

        func mark() {
            lock.withLock { if elapsed == nil { elapsed = ContinuousClock.now - started } }
        }

        var latency: Duration? { lock.withLock { elapsed } }
    }

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
                let prompt = testCase.prompt
                let firstToken = FirstToken()
                let started = ContinuousClock.now
                let output = try await engine.generate(
                    instructions: prompt.instructions, input: prompt.input, maxTokens: prompt.maxTokens,
                    onText: { _ in firstToken.mark() }
                )
                let total = ContinuousClock.now - started
                totals.append(seconds(total).value)
                genSpeeds.append(output.generationTokensPerSecond)
                let cleaned = OutputCleaner.clean(output.text)
                let ttft = firstToken.latency.map { seconds($0).description } ?? "–"
                print("[bench]   \(testCase.name): \(seconds(total)) total, first token \(ttft), \(Int(output.generationTokensPerSecond)) tok/s")
                report += """

                    ### \(testCase.name)

                    \(seconds(total)) total · first token \(ttft) · prompt \(output.promptTokens) tokens at \(Int(output.promptTokensPerSecond)) tok/s · \
                    generated \(output.generatedTokens) tokens at \(Int(output.generationTokensPerSecond)) tok/s

                    \(cleaned.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n"))

                    """
            }

            let peakMLX = Memory.peakMemory
            await coordinator.unload(engine)
            let afterUnload = MemoryFootprint.currentBytes()
            let peakFootprint = lifetimePeakFootprint()
            report += "\nPeak MLX memory \(MemoryFootprint.formatted(UInt64(peakMLX))); process peak footprint \(MemoryFootprint.formatted(peakFootprint)); footprint after unload \(MemoryFootprint.formatted(afterUnload))\n"
            summaryRows.append(
                "| \(modelID.replacingOccurrences(of: "mlx-community/", with: "")) | \(seconds(loadTime)) | "
                    + totals.map { String(format: "%.1f s", $0) }.joined(separator: " | ")
                    + " | \(Int(genSpeeds.reduce(0, +) / Double(genSpeeds.count))) | \(MemoryFootprint.formatted(UInt64(peakMLX))) | \(MemoryFootprint.formatted(peakFootprint)) |"
            )
        }

        let table = """

            ## Summary

            | Model | Load | \(Self.cases.map(\.name).joined(separator: " | ")) | Avg gen tok/s | Peak MLX memory | Process peak footprint |
            |---|---|\(String(repeating: "---|", count: Self.cases.count))---|---|---|
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

    /// Highest physical footprint this process has reached: what the OS has to find room for.
    private func lifetimePeakFootprint() -> UInt64? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? usage.ri_lifetime_max_phys_footprint : nil
    }

    private func machine() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}

