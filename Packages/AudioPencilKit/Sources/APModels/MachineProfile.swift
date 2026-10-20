import Foundation

/// What this Mac (or iPhone) can hold. Model budgets scale with its memory instead of assuming 8 GB.
public struct MachineProfile: Sendable, Equatable {
    public var physicalMemory: UInt64
    /// e.g. "Apple M1"
    public var chip: String
    /// e.g. "MacBookAir10,1"
    public var model: String
    public var performanceCores: Int

    public init(physicalMemory: UInt64, chip: String, model: String, performanceCores: Int) {
        self.physicalMemory = physicalMemory
        self.chip = chip
        self.model = model
        self.performanceCores = performanceCores
    }

    public static let current = MachineProfile(
        physicalMemory: ProcessInfo.processInfo.physicalMemory,
        chip: sysctlString("machdep.cpu.brand_string") ?? "Apple silicon",
        model: sysctlString("hw.model") ?? "Mac",
        performanceCores: sysctlInt("hw.perflevel0.physicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount
    )

    public var memoryGB: Double { Double(physicalMemory) / 1_073_741_824 }

    /// Largest writing model (weights on disk ≈ in memory) worth suggesting: about a third of RAM,
    /// leaving room for macOS, other apps, the KV cache and the Whisper swap. 8 GB → ~2.7 GB.
    public var writingModelBudget: UInt64 { UInt64(Double(physicalMemory) * 0.33) }

    /// Largest transcription model worth suggesting (it stays loaded while idle). 8 GB → ~1 GB.
    public var transcriptionModelBudget: UInt64 { UInt64(Double(physicalMemory) * 0.12) }

    /// Plain-English summary for the UI, e.g. "Apple M1 · 8 GB".
    public var summary: String { "\(chip) · \(Int(memoryGB.rounded())) GB" }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}

/// A model found by discovery that fits this machine and isn't the one in use.
public struct ModelSuggestion: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case transcription, writing }

    /// Hugging Face repo (writing) or WhisperKit folder name (transcription).
    public var id: String
    public var kind: Kind
    public var name: String
    public var sizeBytes: UInt64
    public var downloads: Int?
    public var created: Date?
    /// Why it was suggested, in a few words.
    public var reason: String

    public init(id: String, kind: Kind, name: String, sizeBytes: UInt64, downloads: Int? = nil, created: Date? = nil, reason: String) {
        self.id = id
        self.kind = kind
        self.name = name
        self.sizeBytes = sizeBytes
        self.downloads = downloads
        self.created = created
        self.reason = reason
    }

    public var sizeDescription: String { ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file) }
}

/// Hugging Face Hub API helpers shared by both discoveries.
public enum HubAPI {
    /// Total size of files under `folder` (or the whole repo) matching `suffix`.
    public static func size(ofRepo repo: String, folder: String? = nil, suffix: String, session: URLSession = .shared) async throws -> UInt64 {
        var path = "https://huggingface.co/api/models/\(repo)/tree/main"
        if let folder { path += "/" + (folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folder) }
        guard let url = URL(string: path + "?recursive=true") else { return 0 }
        let (data, _) = try await session.data(from: url)
        struct Entry: Decodable { var path: String; var size: UInt64?; var type: String }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        return entries.filter { $0.type == "file" && $0.path.hasSuffix(suffix) }.reduce(0) { $0 + ($1.size ?? 0) }
    }
}
