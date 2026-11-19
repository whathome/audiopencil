import APCore
import APModels
import Foundation
#if AUDIOPENCIL_LEGACY_TOOLCHAIN
import Hub
#else
import HuggingFace
#endif
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

public enum SummaryEngineError: LocalizedError {
    case notDownloaded(String)
    case notLoaded
    case unsupportedLegacyModel(String)

    public var errorDescription: String? {
        switch self {
        case .notDownloaded(let id): String(localized: "The writing model \(id) hasn't been downloaded.", bundle: .module)
        case .notLoaded: String(localized: "The writing model isn't loaded.", bundle: .module)
        case .unsupportedLegacyModel(let id): String(localized: "The writing model \(id) requires the modern build. Choose Llama 3.2 3B or Qwen3 4B in Settings for this legacy build.", bundle: .module)
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
        if let commit = try? String(contentsOf: repo.appending(path: "refs/main"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !commit.isEmpty {
            return repo.appending(path: "snapshots/\(commit)", directoryHint: .isDirectory)
        }
        #if AUDIOPENCIL_LEGACY_TOOLCHAIN
        return HubApi(downloadBase: cacheDirectory).localRepoLocation(.init(id: modelID))
        #else
        return nil
        #endif
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
        #if AUDIOPENCIL_LEGACY_TOOLCHAIN
        let hub = HubApi(downloadBase: cacheDirectory)
        let configurationDirectory = try await hub.snapshot(from: modelID, matching: ["config.json"])
        try await validateLegacyArchitecture(in: configurationDirectory)
        _ = try await hub.snapshot(
            from: modelID, matching: ["*.safetensors", "*.json", "*.jinja"]
        ) { value in
            progress(value.fractionCompleted)
        }
        #else
        let downloader = makeDownloader()
        _ = try await downloader.download(
            id: modelID, revision: "main",
            matching: ["*.safetensors", "*.json", "*.jinja"],
            useLatest: false
        ) { value in
            progress(value.fractionCompleted)
        }
        #endif
    }

    public func load() async throws {
        try await lock.withLock {
            guard container == nil else { return }
            guard let snapshot = snapshotDirectory, isDownloaded else {
                throw SummaryEngineError.notDownloaded(modelID)
            }
            #if AUDIOPENCIL_LEGACY_TOOLCHAIN
            try await validateLegacyArchitecture(in: snapshot)
            GPU.set(cacheLimit: Self.gpuCacheLimit)
            container = try await LLMModelFactory.shared.loadContainer(configuration: .init(directory: snapshot))
            #else
            Memory.cacheLimit = Self.gpuCacheLimit
            // Load from the local snapshot: no network once downloaded.
            container = try await LLMModelFactory.shared.loadContainer(
                from: snapshot,
                using: TransformersTokenizerLoader()
            )
            #endif
        }
    }

    public func unload() async {
        try? await lock.withLock {
            container = nil
            Self.clearGPUCache()
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
            Self.clearGPUCache()
            try Task.checkCancellation()
            return output
        }
    }

    private static func clearGPUCache() {
        #if AUDIOPENCIL_LEGACY_TOOLCHAIN
        GPU.clearCache()
        #else
        Memory.clearCache()
        #endif
    }

    #if AUDIOPENCIL_LEGACY_TOOLCHAIN
    private func validateLegacyArchitecture(in directory: URL) async throws {
        struct Configuration: Decodable { let model_type: String }
        let configuration = try JSONDecoder().decode(
            Configuration.self, from: Data(contentsOf: directory.appending(path: "config.json"))
        )
        guard await WritingModelDiscovery.supportsArchitecture(configuration.model_type) else {
            throw SummaryEngineError.unsupportedLegacyModel(modelID)
        }
    }
    #endif

    #if !AUDIOPENCIL_LEGACY_TOOLCHAIN
    private func makeDownloader() -> any MLXLMCommon.Downloader {
        HubDownloader(hub: HubClient(host: URL(string: "https://huggingface.co")!, cache: HubCache(cacheDirectory: cacheDirectory)))
    }
    #endif
}
