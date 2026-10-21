import Foundation

/// How long a first-time preparation will take on this Mac. Measured times win; otherwise times from an
/// M1 MacBook Air (docs/benchmarks/multilingual-whisper.md), or a guess from the audio encoder's size,
/// which dominates: compile time grows much faster than size (Small's 170 MB encoder: ~90 s in all;
/// Large v3 Turbo's 410 MB: ~12 min).
public enum PreparationEstimate {
    private static let measuredKey = "modelPreparationSeconds"

    static let referenceSeconds: [String: Double] = [
        "openai_whisper-small.en": 90,
        "openai_whisper-small": 90,
        "openai_whisper-large-v3-v20240930_turbo_632MB": 730,
        "openai_whisper-base.en": 30,
        "openai_whisper-base": 30,
        "openai_whisper-tiny.en": 15,
        "openai_whisper-tiny": 15,
        // Three encoder window sizes, each compiled (docs/benchmarks/phonon-2-vs-whisper-small.md).
        "fluidinference_phonon-2": 320,
    ]

    public static func seconds(variant: String, folder: URL) -> Double {
        if let measured = (UserDefaults.standard.dictionary(forKey: measuredKey) as? [String: Double])?[variant] {
            return measured
        }
        if let reference = referenceSeconds[variant] { return reference }
        let encoderMB = Double(folderSize(folder.appending(path: "AudioEncoder.mlmodelc"))) / 1_000_000
        guard encoderMB > 0 else { return 300 }
        return max(15, 90 * pow(encoderMB / 170, 2.8))
    }

    public static func record(_ seconds: Double, variant: String) {
        var measured = UserDefaults.standard.dictionary(forKey: measuredKey) as? [String: Double] ?? [:]
        measured[variant] = seconds
        UserDefaults.standard.set(measured, forKey: measuredKey)
    }

    private static func folderSize(_ url: URL) -> UInt64 {
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: UInt64 = 0
        for case let file as URL in files {
            total += UInt64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}
