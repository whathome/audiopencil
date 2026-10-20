import APModels
import Foundation
import MLXLLM

/// Finds MLX chat models on Hugging Face that this machine can run (PRD "Model discovery"):
/// 4-bit text-generation models from mlx-community whose architecture MLX supports and whose weights
/// fit the machine's budget. Ranked by fit, popularity and recency. Suggests only; never switches.
public enum WritingModelDiscovery {
    struct HubModel: Decodable {
        var id: String
        var downloads: Int?
        var createdAt: Date?
        var pipeline_tag: String?
        var tags: [String]?
        var config: Config?
        struct Config: Decodable { var model_type: String? }
    }

    /// Names that aren't general writing models.
    static let excluded = [
        "coder", "math", "guard", "embed", "vl", "vision", "reward", "-base", "audio", "ocr", "tts", "draft", "mtp",
        "uncensored", "abliterated", "heretic", "roleplay", "-rp", "reap",
    ]

    public static func suggestions(
        for machine: MachineProfile = .current,
        excluding known: Set<String>,
        limit: Int = 5,
        session: URLSession = .shared
    ) async throws -> [ModelSuggestion] {
        var candidates: [String: HubModel] = [:]
        for query in ["Instruct-4bit", "-it-4bit", "4bit"] {
            for model in try await search(query, session: session) where candidates[model.id] == nil {
                candidates[model.id] = model
            }
        }

        var plausible: [HubModel] = []
        for model in candidates.values {
            let lower = model.id.lowercased()
            guard model.pipeline_tag == "text-generation", lower.contains("4bit"),
                  !known.contains(model.id), !excluded.contains(where: lower.contains),
                  let type = model.config?.model_type, await LLMTypeRegistry.shared.contains(type)
            else { continue }
            plausible.append(model)
        }
        // Most popular first, then check sizes for the top few (one request each).
        plausible.sort { ($0.downloads ?? 0) > ($1.downloads ?? 0) }

        var sized: [(HubModel, UInt64)] = []
        for model in plausible.prefix(20) {
            guard let bytes = try? await HubAPI.size(ofRepo: model.id, suffix: ".safetensors", session: session),
                  bytes >= minimumSize(for: machine), bytes <= machine.writingModelBudget
            else { continue }
            sized.append((model, bytes))
        }

        let now = Date()
        let ranked = sized.map { model, bytes -> (ModelSuggestion, Double) in
            let popularity = log10(Double(max(model.downloads ?? 1, 1)))
            let ageYears = model.createdAt.map { now.timeIntervalSince($0) / 31_536_000 } ?? 3
            let recency = max(0, 2 - ageYears) // newer models are usually better at a given size
            let fit = Double(bytes) / Double(machine.writingModelBudget) // bigger (within budget) writes better
            let score = popularity + 1.5 * recency + 2 * fit
            let reason = [
                model.createdAt.map { "released \($0.formatted(.dateTime.month(.abbreviated).year()))" },
                model.downloads.map { "\($0.formatted(.number.notation(.compactName))) downloads last month" },
                "fits \(machine.summary)",
            ].compactMap { $0 }.joined(separator: " · ")
            let name = model.id.replacingOccurrences(of: "mlx-community/", with: "")
            return (ModelSuggestion(id: model.id, kind: .writing, name: name, sizeBytes: bytes, downloads: model.downloads, created: model.createdAt, reason: reason), score)
        }
        return ranked.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// Small models write noticeably worse; don't offer them as upgrades. 8 GB → 1.2 GB, 64 GB → ~5 GB.
    static func minimumSize(for machine: MachineProfile) -> UInt64 {
        max(1_200_000_000, machine.writingModelBudget / 4)
    }

    static func search(_ query: String, session: URLSession) async throws -> [HubModel] {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        components.queryItems = [
            URLQueryItem(name: "author", value: "mlx-community"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "60"),
        ] + ["downloads", "createdAt", "pipeline_tag", "tags", "config"].map { URLQueryItem(name: "expand[]", value: $0) }
        let (data, _) = try await session.data(from: components.url!)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) ?? .distantPast
        }
        return try decoder.decode([HubModel].self, from: data)
    }
}
