import APCore
import APModels
import APTranscription
import Foundation

/// Dictation languages: one per recording, remembered per app on this Mac, routed to the right Whisper model.
extension AppModel {
    static let languageMemoryKey = "languageMemory"

    static func loadLanguageMemory() -> LanguageMemory {
        guard let data = UserDefaults.standard.data(forKey: languageMemoryKey),
              let memory = try? JSONDecoder().decode(LanguageMemory.self, from: data)
        else { return LanguageMemory() }
        return memory
    }

    func saveLanguageMemory() {
        if let data = try? JSONEncoder().encode(languageMemory) {
            UserDefaults.standard.set(data, forKey: Self.languageMemoryKey)
        }
    }

    /// Languages for the pill and Settings, always including the active one.
    var offeredLanguages: [SpokenLanguage] { settings.offeredLanguages(including: activeLanguage) }

    /// More than one language in use: show the language badge and menu section.
    var isMultilingual: Bool { offeredLanguages.count > 1 || !activeLanguage.isEnglish }

    /// Whether the current writing model can write `language`; if not, styles paste the raw transcript.
    func canStyle(in language: SpokenLanguage) -> Bool {
        WritingLanguages.canWrite(language.code, withModel: settings.writingModel)
    }

    /// Makes `language` the one Whisper transcribes, swapping models when it needs the other one.
    func useLanguage(_ language: SpokenLanguage) {
        activeLanguage = language
        let variant = settings.transcriptionVariant(for: language)
        if whisper.variant != variant {
            switchModel(to: variant)
        } else {
            let engine = whisper
            let vocabulary = settings.vocabulary(for: language)
            Task {
                await engine.setLanguage(language.code)
                await engine.setVocabulary(vocabulary)
            }
        }
    }

    /// With any non-English language in the list, get the multilingual model ready now: download it
    /// (0.5–0.6 GB) and prepare it for this Mac (Core ML compiles it once, up to ~15 min on an M1), so the
    /// first dictation in another language doesn't wait. Dictation in any language waits while it prepares,
    /// so this happens right after the language is added, with progress in Settings.
    func prefetchMultilingualModel() {
        guard multilingualDownloadTask == nil, offeredLanguages.contains(where: { !$0.isEnglish }) else { return }
        let engine = WhisperEngine(variant: settings.multilingualTranscriptionModel)
        guard !engine.isDownloaded || engine.needsFirstTimePreparation else { return }
        multilingualDownloadVariant = engine.variant
        multilingualDownloadTask = Task {
            do {
                if !engine.isDownloaded {
                    multilingualDownload = 0
                    try await engine.download { fraction in
                        Task { @MainActor [weak self] in if self?.multilingualDownload != nil { self?.multilingualDownload = fraction } }
                    }
                    multilingualDownload = nil
                }
                // When it's already the current model, loading it for dictation prepares it anyway.
                if engine.needsFirstTimePreparation, engine.variant != whisper.variant {
                    multilingualPreparing = true
                    await observePreparation(of: engine)
                    let start = ContinuousClock.now
                    try await coordinator.ensureLoaded(engine) // swaps the current Whisper model out meanwhile
                    await coordinator.unload(engine)
                    Log.models.notice("Prepared \(engine.variant, privacy: .public) for this Mac in \(ContinuousClock.now - start, privacy: .public)")
                    multilingualPreparing = false
                    multilingualDownloadTask = nil // so the reload below doesn't wait on this task
                    multilingualDownloadVariant = nil
                    prepareModel() // back to the model for the current language
                }
            } catch {
                Log.models.error("Multilingual model download failed: \(error.localizedDescription, privacy: .public)")
            }
            multilingualDownload = nil
            multilingualPreparing = false
            multilingualDownloadTask = nil
            multilingualDownloadVariant = nil
        }
    }

    /// Settings › Dictation languages: pick the language for the frontmost-app-independent default.
    func chooseDefaultLanguage(_ language: SpokenLanguage) {
        languageMemory.remember(language, forApp: nil)
        if dictation.phase == .idle { useLanguage(language) }
    }
}
