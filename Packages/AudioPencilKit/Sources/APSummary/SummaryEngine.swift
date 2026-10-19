import APCore
import APModels
import Foundation
import HuggingFace
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

public enum SummaryEngineError: LocalizedError {
    case notDownloaded(String)
    case notLoaded

    public var errorDescription: String? {
        switch self {
        case .notDownloaded(let id): "The writing model \(id) hasn't been downloaded."
        case .notLoaded: "The writing model isn't loaded."
        }
    }
}

public struct SummaryOutput: Sendable {
    public var text: String
    public var promptTokens: Int
    public var generatedTokens: Int
    /// Prompt processing ("prefill") time.
    public var promptSeconds: Double
    public var generationSeconds: Double

    public var promptTokensPerSecond: Double { promptSeconds > 0 ? Double(promptTokens) / promptSeconds : 0 }
    public var generationTokensPerSecond: Double { generationSeconds > 0 ? Double(generatedTokens) / generationSeconds : 0 }
}

/// MLX language model used to rewrite transcripts into styles.
/// Residency is owned by `ModelCoordinator`, which unloads Whisper first: on 8 GB the two never coexist.
public actor SummaryEngine: ManagedModel {
    public nonisolated let kind = ModelKind.summarization
    /// Hugging Face repository, e.g. "mlx-community/Qwen3-4B-4bit".
    public nonisolated let modelID: String
    public nonisolated var displayName: String { modelID.components(separatedBy: "/").last ?? modelID }

    private let root: URL
    private var container: ModelContainer?
    private let lock = AsyncLock()

    /// MLX keeps freed GPU buffers for reuse; cap that cache so it doesn't sit on memory between dictations.
    private static let gpuCacheLimit = 128 * 1024 * 1024

    public init(modelID: String, root: URL = ModelLocations.root) {
        self.modelID = modelID
        self.root = root
    }

    public var isLoaded: Bool { container != nil }

    private nonisolated var cacheDirectory: URL { root.appending(path: "huggingface", directoryHint: .isDirectory) }

    /// Snapshot folder inside the Hugging Face cache layout: models--org--name/snapshots/<commit>.
    private nonisolated var snapshotDirectory: URL? {
        let repo = cacheDirectory.appending(path: "models--" + modelID.replacingOccurrences(of: "/", with: "--"))
        guard let commit = try? String(contentsOf: repo.appending(path: "refs/main"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !commit.isEmpty
        else { return nil }
        return repo.appending(path: "snapshots/\(commit)", directoryHint: .isDirectory)
    }

    /// Weights and tokenizer are on disk, so loading needs no network.
    public nonisolated var isDownloaded: Bool {
        guard let snapshot = snapshotDirectory,
              FileManager.default.fileExists(atPath: snapshot.appending(path: "config.json").path),
              let files = try? FileManager.default.contentsOfDirectory(atPath: snapshot.path)
        else { return false }
        return files.contains { $0.hasSuffix(".safetensors") }
    }

    /// Downloads weights and tokenizer from Hugging Face. `progress` receives 0…1.
    public func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        Log.models.info("Downloading \(self.modelID, privacy: .public)")
        let downloader = makeDownloader()
        _ = try await downloader.download(
            id: modelID, revision: "main",
            matching: ["*.safetensors", "*.json", "*.jinja"],
            useLatest: false
        ) { value in
            progress(value.fractionCompleted)
        }
    }

    public func load() async throws {
        try await lock.withLock {
            guard container == nil else { return }
            guard let snapshot = snapshotDirectory, isDownloaded else {
                throw SummaryEngineError.notDownloaded(modelID)
            }
            Memory.cacheLimit = Self.gpuCacheLimit
            // Load from the local snapshot: no network once downloaded.
            container = try await LLMModelFactory.shared.loadContainer(
                from: snapshot,
                using: TransformersTokenizerLoader()
            )
        }
    }

    public func unload() async {
        try? await lock.withLock {
            container = nil
            Memory.clearCache()
        }
    }

    /// Generates a response to `input` under `instructions` (the system prompt).
    /// `onText` receives the text so far as it streams.
    public func generate(
        instructions: String,
        input: String,
        maxTokens: Int,
        temperature: Float = 0.3,
        onText: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> SummaryOutput {
        try await lock.withLock {
            guard let container else { throw SummaryEngineError.notLoaded }
            let parameters = GenerateParameters(maxTokens: maxTokens, temperature: temperature, topP: 0.9)
            let output = try await container.perform { context in
                let userInput = UserInput(
                    chat: [.system(instructions), .user(input)],
                    // Qwen3 templates think out loud unless told not to; other templates ignore this.
                    additionalContext: ["enable_thinking": false]
                )
                let prepared = try await context.processor.prepare(input: userInput)
                var text = ""
                var info: GenerateCompletionInfo?
                for await item in try MLXLMCommon.generate(input: prepared, parameters: parameters, context: context) {
                    if Task.isCancelled { break } // Esc: stop generating
                    switch item {
                    case .chunk(let chunk):
                        text += chunk
                        onText(text)
                    case .info(let completion):
                        info = completion
                    default:
                        break
                    }
                }
                return SummaryOutput(
                    text: text,
                    promptTokens: info?.promptTokenCount ?? 0,
                    generatedTokens: info?.generationTokenCount ?? 0,
                    promptSeconds: info?.promptTime ?? 0,
                    generationSeconds: info?.generateTime ?? 0
                )
            }
            Memory.clearCache()
            try Task.checkCancellation()
            return output
        }
    }

    private func makeDownloader() -> any MLXLMCommon.Downloader {
        HubDownloader(hub: HubClient(host: URL(string: "https://huggingface.co")!, cache: HubCache(cacheDirectory: cacheDirectory)))
    }
}
