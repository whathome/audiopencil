import Foundation

/// Curated transcription models. Milestone 6 adds automatic Hugging Face discovery on top.
public struct TranscriptionModelOption: Identifiable, Hashable, Sendable {
    /// WhisperKit folder name in the `argmaxinc/whisperkit-coreml` repository.
    public let id: String
    public let name: String
    public let note: String
    public let approximateDownloadMB: Int

    public static let catalogue: [TranscriptionModelOption] = [
        .init(id: "openai_whisper-small.en", name: "Small (English)", note: "Recommended: keeps up live on any Apple silicon Mac", approximateDownloadMB: 480),
        .init(id: "openai_whisper-base.en", name: "Base (English)", note: "Faster, less accurate", approximateDownloadMB: 140),
        .init(id: "openai_whisper-tiny.en", name: "Tiny (English)", note: "Fastest; for testing", approximateDownloadMB: 75),
    ]

    /// Models for languages other than English (any Whisper language). Notes from
    /// docs/benchmarks/multilingual-whisper.md.
    public static let multilingualCatalogue: [TranscriptionModelOption] = [
        .init(id: "openai_whisper-large-v3-v20240930_turbo_632MB", name: "Large v3 Turbo (multilingual)", note: "Recommended: far more accurate, about as fast; first use prepares for ~12 min", approximateDownloadMB: 632),
        .init(id: "openai_whisper-small", name: "Small (multilingual)", note: "Lighter; can drop words, especially in Spanish", approximateDownloadMB: 480),
        .init(id: "openai_whisper-base", name: "Base (multilingual)", note: "Faster, less accurate", approximateDownloadMB: 140),
    ]

    public static func option(for id: String) -> TranscriptionModelOption? {
        (catalogue + multilingualCatalogue).first { $0.id == id }
    }
}

/// Curated MLX writing models that fit even an 8 GB Mac. Discovery suggests bigger ones on bigger machines.
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

/// Which languages a writing model can write well, from its model card. Styles in other languages
/// fall back to the raw transcript.
public enum WritingLanguages {
    /// nil means broadly multilingual (dozens of languages, including all common ones).
    public static func supported(byModel id: String) -> Set<String>? {
        let name = id.lowercased()
        if name.contains("smollm3") { return ["en", "fr", "es", "de", "it", "pt"] }
        if name.contains("llama-3") { return ["en", "de", "fr", "it", "pt", "hi", "es", "th"] }
        if name.contains("qwen") || name.contains("gemma") || name.contains("aya") || name.contains("mistral-small") { return nil }
        return ["en"] // unknown: only promise English
    }

    public static func canWrite(_ language: String, withModel id: String) -> Bool {
        supported(byModel: id)?.contains(language) ?? true
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
