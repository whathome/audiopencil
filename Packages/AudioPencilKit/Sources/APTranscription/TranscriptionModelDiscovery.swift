import APCore
import APModels
import Foundation
import WhisperKit

/// Finds WhisperKit models this device supports (Argmax's per-chip support list) that fit the machine's
/// transcription budget and are a step up from the current ones: English-only models for English, and
/// multilingual ones when other languages are in use. Suggests only.
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

    static func isEnglishOnly(_ variant: String) -> Bool {
        DictationSettings.isEnglishOnly(variant)
    }

    /// `multilingualCurrent` is the model for other languages, or nil when only English is in use.
    public static func suggestions(
        for machine: MachineProfile = .current,
        current: String,
        multilingualCurrent: String? = nil,
        session: URLSession = .shared
    ) async throws -> [ModelSuggestion] {
        let support = await WhisperKit.recommendedRemoteModels()
        var result: [ModelSuggestion] = []
        for variant in support.supported {
            let kind: ModelSuggestion.Kind
            if isEnglishOnly(variant), variant != current, tier(variant) > tier(current) {
                kind = .transcription
            } else if let multilingualCurrent, !isEnglishOnly(variant), variant != multilingualCurrent, tier(variant) > tier(multilingualCurrent) {
                kind = .multilingualTranscription
            } else {
                continue
            }
            let bytes = (try? await HubAPI.size(ofRepo: ModelLocations.whisperRepository, folder: variant, suffix: "", session: session)) ?? 0
            guard bytes > 0, bytes <= machine.transcriptionModelBudget else { continue }
            let reason = kind == .transcription
                ? String(localized: "more accurate English than your current model; supported on \(machine.chip); may be slower to keep up live", bundle: .module)
                : String(localized: "more accurate for your other languages; supported on \(machine.chip); may be slower to keep up live", bundle: .module)
            result.append(ModelSuggestion(id: variant, kind: kind, name: variant.replacingOccurrences(of: "openai_whisper-", with: "Whisper "), sizeBytes: bytes, reason: reason))
        }
        return result.sorted { tier($0.id) < tier($1.id) } // smallest step up first
    }
}
