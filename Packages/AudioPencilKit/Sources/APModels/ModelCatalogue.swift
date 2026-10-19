import Foundation

/// Curated transcription models. Milestone 6 adds automatic Hugging Face discovery on top.
public struct TranscriptionModelOption: Identifiable, Hashable, Sendable {
    /// WhisperKit folder name in the `argmaxinc/whisperkit-coreml` repository.
    public let id: String
    public let name: String
    public let note: String
    public let approximateDownloadMB: Int

    public static let catalogue: [TranscriptionModelOption] = [
        .init(id: "openai_whisper-small.en", name: "Small (English)", note: "Recommended on M1 with 8 GB", approximateDownloadMB: 480),
        .init(id: "openai_whisper-base.en", name: "Base (English)", note: "Faster, less accurate", approximateDownloadMB: 140),
        .init(id: "openai_whisper-tiny.en", name: "Tiny (English)", note: "Fastest; for testing", approximateDownloadMB: 75),
    ]

    public static func option(for id: String) -> TranscriptionModelOption? {
        catalogue.first { $0.id == id }
    }
}

/// Curated MLX writing models that fit an 8 GB Mac alongside the system (one at a time with Whisper).
/// Notes come from docs/benchmarks/summary-models-m1-8gb.md.
public struct WritingModelOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let note: String
    public let approximateDownloadGB: Double

    public static let catalogue: [WritingModelOption] = [
        .init(id: "mlx-community/SmolLM3-3B-4bit", name: "SmolLM3 3B", note: "Recommended: most faithful to what you said", approximateDownloadGB: 1.7),
        .init(id: "mlx-community/Qwen3.5-2B-4bit", name: "Qwen3.5 2B", note: "Fastest and lightest; occasionally invents details", approximateDownloadGB: 1.7),
        .init(id: "mlx-community/Llama-3.2-3B-Instruct-4bit", name: "Llama 3.2 3B", note: "Tends to add things you didn't say", approximateDownloadGB: 1.8),
        .init(id: "mlx-community/Qwen3-4B-4bit", name: "Qwen3 4B", note: "Slowest and heaviest on 8 GB", approximateDownloadGB: 2.3),
    ]

    public static func option(for id: String) -> WritingModelOption? {
        catalogue.first { $0.id == id }
    }
}

public enum ModelLocations {
    public static let whisperRepository = "argmaxinc/whisperkit-coreml"

    /// ~/Library/Application Support/AudioPencil/Models
    public static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "AudioPencil/Models", directoryHint: .isDirectory)
    }

    /// Where the Hugging Face snapshot of a WhisperKit model lands.
    public static func whisperFolder(variant: String, root: URL = root) -> URL {
        root.appending(path: "models/\(whisperRepository)/\(variant)", directoryHint: .isDirectory)
    }
}
