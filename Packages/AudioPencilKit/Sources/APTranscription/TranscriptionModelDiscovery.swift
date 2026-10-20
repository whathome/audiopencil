import APModels
import Foundation
import WhisperKit

/// Finds English WhisperKit models this device supports (Argmax's per-chip support list) that fit the
/// machine's transcription budget and are a step up from the current one. Suggests only.
public enum TranscriptionModelDiscovery {
    /// Rough accuracy ladder; distil-large-v3 is English-only and close to large-v3.
    static func tier(_ variant: String) -> Int {
        let lower = variant.lowercased()
        if lower.contains("large") { return lower.contains("distil") ? 4 : 5 }
        if lower.contains("medium") { return 3 }
        if lower.contains("small") { return 2 }
        if lower.contains("base") { return 1 }
        return 0
    }

    /// The PRD wants an English-only model: ".en" variants, or distil-whisper (English-only).
    static func isEnglishOnly(_ variant: String) -> Bool {
        variant.contains(".en") || variant.lowercased().contains("distil")
    }

    public static func suggestions(
        for machine: MachineProfile = .current,
        current: String,
        session: URLSession = .shared
    ) async throws -> [ModelSuggestion] {
        let support = await WhisperKit.recommendedRemoteModels()
        let currentTier = tier(current)
        var result: [ModelSuggestion] = []
        for variant in support.supported where isEnglishOnly(variant) && variant != current && tier(variant) > currentTier {
            let bytes = (try? await HubAPI.size(ofRepo: ModelLocations.whisperRepository, folder: variant, suffix: "", session: session)) ?? 0
            guard bytes > 0, bytes <= machine.transcriptionModelBudget else { continue }
            let reason = "more accurate than your current model; supported on \(machine.chip); may be slower to keep up live"
            result.append(ModelSuggestion(id: variant, kind: .transcription, name: variant.replacingOccurrences(of: "openai_whisper-", with: "Whisper "), sizeBytes: bytes, reason: reason))
        }
        return result.sorted { tier($0.id) < tier($1.id) } // smallest step up first
    }
}
