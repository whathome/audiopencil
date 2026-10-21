import APCore
import APModels
import APPhonon
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

    /// Makes `language` the one Whisper transcribes, swapping models when it needs the other one.
    func useLanguage(_ language: SpokenLanguage) {
        activeLanguage = language
        let variant = transcriptionVariant(for: language)
        if speech.variant != variant {
            switchModel(to: variant)
        } else {
            let engine = speech
            let vocabulary = settings.vocabulary(for: language)
            Task {
                await engine.setLanguage(language.code)
                await engine.setVocabulary(vocabulary)
            }
        }
    }

    // MARK: Best model that's ready

    static let starterMultilingualModel = SpeechModels.starter

    static func multilingualTarget(_ settings: DictationSettings, machine: MachineProfile = .current) -> String {
        SpeechModels.multilingualTarget(settings, machine: machine)
    }

    /// Whisper as `SpeechModels` picks it, except English while trying Phonon-2 out and no vocabulary is set:
    /// Phonon-2 has no prompt to steer spelling, so Whisper keeps a vocabulary working.
    static func bestVariant(for language: SpokenLanguage, settings: DictationSettings) -> String {
        var vocabularyAllows = settings.vocabulary(for: language).isEmpty
        #if DEBUG
        vocabularyAllows = vocabularyAllows || debugPhononIgnoresVocabulary
        #endif
        if language.isEnglish, UserDefaults.standard.bool(forKey: phononTrialKey), vocabularyAllows {
            return PhononEngine.variant
        }
        return SpeechModels.bestVariant(for: language, settings: settings)
    }

    static func engine(for variant: String) -> any DictationEngine {
        variant == PhononEngine.variant ? PhononEngine() : WhisperEngine(variant: variant)
    }

    // MARK: Phonon-2 trial

    static let phononTrialKey = "phononTrial"

    #if DEBUG
    /// Debug builds (phonon:force): Phonon-2 even with a vocabulary set, without touching the synced list.
    static var debugPhononIgnoresVocabulary = false
    #endif

    /// Settings › Dictation: English through Phonon-2 instead of Whisper. On this Mac only, not synced.
    var phononTrial: Bool {
        get {
            access(keyPath: \.phononTrial)
            return UserDefaults.standard.bool(forKey: Self.phononTrialKey)
        }
        set {
            withMutation(keyPath: \.phononTrial) { UserDefaults.standard.set(newValue, forKey: Self.phononTrialKey) }
            Log.models.notice("Phonon-2 trial \(newValue ? "on" : "off", privacy: .public)")
            if speech.variant != transcriptionVariant(for: activeLanguage) {
                switchModel(to: transcriptionVariant(for: activeLanguage))
            }
        }
    }

    /// "Whisper Small (English)" or "Phonon-2", for status lines.
    func speechModelName(_ variant: String) -> String {
        variant == PhononEngine.variant ? "Phonon-2" : "Whisper " + (TranscriptionModelOption.option(for: variant)?.name ?? variant)
    }

    /// English is going through Phonon-2 right now.
    var usesPhonon: Bool { transcriptionVariant(for: .english) == PhononEngine.variant }

    func transcriptionVariant(for language: SpokenLanguage) -> String {
        _ = phononTrial // observed, so what views show follows the trial switch
        return Self.bestVariant(for: language, settings: settings)
    }

    /// A recording in this language is on the starter model while the better one prepares.
    func isUsingStarterModel(_ language: SpokenLanguage) -> Bool {
        transcriptionVariant(for: language) == Self.starterMultilingualModel
            && Self.multilingualTarget(settings) != Self.starterMultilingualModel
    }

    /// Said once per language per run, when a recording starts on the starter model.
    func starterNote(for language: SpokenLanguage) -> String? {
        guard isUsingStarterModel(language), !starterNoteShown.contains(language.code) else { return nil }
        starterNoteShown.insert(language.code)
        let target = Self.multilingualTarget(settings)
        if let preparation, preparation.variant == target {
            let left = max(1, Int(((preparation.estimatedSeconds - Date().timeIntervalSince(preparation.startedAt)) / 60).rounded(.up)))
            return String(localized: "\(language.name()) uses a quicker starter model until the more accurate one is ready, in about \(left) min.")
        }
        return String(localized: "\(language.name()) uses a quicker starter model until the more accurate one is ready.")
    }

    // MARK: Background preparation

    /// With any non-English language in use, get its models ready in the background, one at a time:
    /// the starter model, then the better one. Each is downloaded and prepared without being loaded,
    /// so the model in use stays loaded and dictation never waits. Pauses while memory is tight.
    func prepareInBackground() {
        guard multilingualQueue == nil, offeredLanguages.contains(where: { !$0.isEnglish }) else { return }
        var variants = [Self.starterMultilingualModel]
        let target = Self.multilingualTarget(settings)
        if target != Self.starterMultilingualModel { variants.append(target) }
        let pending = variants.filter { !WhisperEngine(variant: $0).isReady }
        guard !pending.isEmpty else { return }

        multilingualQueue = Task {
            _ = try? await modelTask?.value // the model in use comes first
            for variant in pending {
                while memoryPressure != .normal { try? await Task.sleep(for: .seconds(30)) }
                // Loading it for dictation prepares it anyway; don't compile it twice.
                if variant == speech.variant, modelTask != nil { _ = try? await modelTask?.value }
                let engine = WhisperEngine(variant: variant)
                guard !engine.isReady else { continue }
                multilingualDownloadVariant = variant
                let job = Task { @MainActor in
                    do {
                        if !engine.isDownloaded {
                            multilingualDownload = 0
                            try await engine.download { fraction in
                                Task { @MainActor [weak self] in if self?.multilingualDownload != nil { self?.multilingualDownload = fraction } }
                            }
                            multilingualDownload = nil
                        }
                        await observePreparation(of: engine)
                        try await engine.prepareIfNeeded()
                    } catch {
                        Log.models.error("Background preparation of \(variant, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                multilingualJob = job
                await job.value
                multilingualJob = nil
                multilingualDownloadVariant = nil
                multilingualDownload = nil
                switchToBestModelWhenIdle()
            }
            multilingualQueue = nil
        }
    }

    /// After a better model becomes ready, move to it between recordings, never during one.
    func switchToBestModelWhenIdle() {
        Task {
            while dictation.phase != .idle { try? await Task.sleep(for: .seconds(1)) }
            let best = transcriptionVariant(for: activeLanguage)
            if speech.variant != best {
                Log.models.notice("Switching to \(best, privacy: .public): ready for this Mac")
                switchModel(to: best)
            }
        }
    }

    /// Settings › Dictation languages: pick the language for the frontmost-app-independent default.
    func chooseDefaultLanguage(_ language: SpokenLanguage) {
        languageMemory.remember(language, forApp: nil)
        if dictation.phase == .idle { useLanguage(language) }
    }
}
