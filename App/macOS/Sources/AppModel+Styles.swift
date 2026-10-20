import APCore
import APModels
import APSummary
import APSync
import AppKit

/// Styles, per-app defaults and the MLX writing model.
extension AppModel {
    // MARK: Styles

    private static let seenPresetsKey = "seenPresetStyles"

    static func loadStyles() -> [Style] {
        let seen = Set(UserDefaults.standard.stringArray(forKey: seenPresetsKey) ?? [])
        UserDefaults.standard.set(Style.presets.map(\.id), forKey: seenPresetsKey)
        guard let data = UserDefaults.standard.data(forKey: stylesKey),
              var saved = try? JSONDecoder().decode([Style].self, from: data)
        else { return Style.presets }
        // Presets added in a later version appear once. A preset that was deleted (here or in the
        // vault settings file) stays deleted. Raw is always there.
        let legacy = seen.isEmpty // before this was tracked: every preset already shipped counts as seen
        for preset in Style.presets where !saved.contains(where: { $0.id == preset.id }) {
            if preset.isRaw || (!legacy && !seen.contains(preset.id)) { saved.append(preset) }
        }
        return saved
    }

    func saveStyles() {
        if let data = try? JSONEncoder().encode(styles) {
            UserDefaults.standard.set(data, forKey: Self.stylesKey)
        }
        applyPickerSettings()
        if !applyingSync { sync?.syncSoon() }
    }

    // MARK: Vault settings file

    /// The app's side of the settings file, built on the last agreed version so fields the app
    /// doesn't edit (tags, other devices) carry over unchanged.
    func localConfig(from base: SharedConfig?) -> SharedConfig {
        var config = base ?? SharedConfig()
        config.styles = styles.map(ConfigStyle.init)
        config.vocabulary = settings.customVocabulary
        config.tags = tags
        config.writingSamples = writingSamples
        config.expireRegularAudio = expireRegularAudio
        config.devices[sync.deviceName] = DeviceSection(settings)
        return config
    }

    /// Applies a merged settings file: shared styles and vocabulary, plus this device's section.
    func apply(_ config: SharedConfig) {
        applyingSync = true
        defer { applyingSync = false }
        var synced = config.styles.map(\.style)
        if !synced.contains(where: \.isRaw) { synced.insert(.raw, at: 0) }
        if synced != styles { styles = synced }
        var updated = settings
        updated.customVocabulary = config.vocabulary
        config.devices[sync.deviceName]?.apply(to: &updated)
        if updated != settings { settings = updated }
        if config.tags != tags { tags = config.tags }
        if config.writingSamples != writingSamples { writingSamples = config.writingSamples }
        if config.expireRegularAudio != expireRegularAudio { expireRegularAudio = config.expireRegularAudio }
    }

    // MARK: Like me

    static func loadWritingSamples() -> [WritingSample] {
        guard let data = UserDefaults.standard.data(forKey: "writingSamples"),
              let samples = try? JSONDecoder().decode([WritingSample].self, from: data) else { return [] }
        return samples
    }

    func writingSamplesChanged(from old: [WritingSample]) {
        if let data = try? JSONEncoder().encode(writingSamples) {
            UserDefaults.standard.set(data, forKey: "writingSamples")
        }
        // Turn "Like me" on once there's enough to imitate (once; after that it's the user's switch).
        let key = "likeMeAutoEnabled"
        if writingSamples.count >= InterviewPrompt.minimumSamples, !UserDefaults.standard.bool(forKey: key),
           let index = styles.firstIndex(where: { $0.tone == .likeMe }) {
            UserDefaults.standard.set(true, forKey: key)
            styles[index].isEnabled = true
        }
        if !applyingSync, writingSamples != old { sync?.syncSoon() }
    }

    func saveSample(_ sample: WritingSample) {
        if let index = writingSamples.firstIndex(where: { $0.id == sample.id }) {
            writingSamples[index] = sample
        } else {
            writingSamples.append(sample)
        }
    }

    /// Style prompt, with the closest writing samples for "Like me".
    func stylePrompt(for style: Style, transcript: String, context: PromptBuilder.Context, language: SpokenLanguage) -> StylePrompt {
        let vocabulary = settings.vocabulary(for: language)
        guard style.tone == .likeMe else {
            return PromptBuilder.prompt(for: style, transcript: transcript, context: context, vocabulary: vocabulary, language: language)
        }
        let examples = WritingSampleSelector.pick(for: transcript, from: writingSamples, language: language)
        return PromptBuilder.prompt(for: style, transcript: transcript, context: context, vocabulary: vocabulary, language: language, examples: examples)
    }

    static func loadStyleMemory() -> StyleMemory {
        guard let data = UserDefaults.standard.data(forKey: styleMemoryKey),
              let memory = try? JSONDecoder().decode(StyleMemory.self, from: data)
        else { return StyleMemory() }
        return memory
    }

    func saveStyleMemory() {
        if let data = try? JSONEncoder().encode(styleMemory) {
            UserDefaults.standard.set(data, forKey: Self.styleMemoryKey)
        }
    }

    func enabledStyle(shortcut: Int) -> Style? {
        styles.first { $0.isEnabled && $0.shortcut == shortcut }
    }

    func applyPickerSettings() {
        dictation?.pickAfterStop = settings.pickStyleAfterStop
        dictation?.pickerAutoConfirm = settings.pickerAutoConfirm
        dictation?.pickerStyles = styles.filter(\.isEnabled).sorted { ($0.shortcut ?? 99) < ($1.shortcut ?? 99) }
    }

    func resetStyle(_ id: String) {
        guard let preset = Style.presets.first(where: { $0.id == id }),
              let index = styles.firstIndex(where: { $0.id == id })
        else { return }
        styles[index] = preset
    }

    // MARK: Writing model

    var writingModelOption: WritingModelOption? { WritingModelOption.option(for: settings.writingModel) }
    var writingModelDownloaded: Bool { writing.isDownloaded }

    func downloadWritingModel() {
        guard writingTask == nil else { return }
        let engine = writing
        writingModelState = .downloading(0)
        writingTask = Task {
            do {
                try await engine.download { fraction in
                    Task { @MainActor [weak self] in
                        if case .downloading = self?.writingModelState { self?.writingModelState = .downloading(fraction) }
                    }
                }
                if engine === writing { writingModelState = .idle }
            } catch {
                if engine === writing { writingModelState = .failed(error.localizedDescription) }
            }
            writingTask = nil
        }
    }

    func switchWritingModel(to id: String) {
        let old = writing
        writing = SummaryEngine(modelID: id)
        writingModelState = .idle
        Task { await coordinator.unload(old) }
    }

    /// Picker open with a styled default: swap Whisper out for the writing model while the user looks.
    /// Only called once the transcript is finished, so Whisper is no longer needed.
    func prefetchWritingModel() {
        let engine = writing
        guard engine.isDownloaded, memoryPressure != .critical else { return }
        Task {
            writingModelState = .loading(firstTime: false)
            modelState = .idle
            try? await coordinator.ensureLoaded(engine)
            writingModelState = .ready
        }
    }

    /// Turns a transcript into `style` with the writing model, then reloads Whisper in the background.
    func rewrite(
        _ transcript: String,
        style: Style,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> String {
        let engine = writing
        guard engine.isDownloaded else { throw RewriteError.modelNotDownloaded }
        guard memoryPressure != .critical else { throw RewriteError.lowMemory }
        let language = dictation.language
        guard canStyle(in: language) else {
            throw RewriteError.languageUnsupported(language: language.name(), model: writingModelOption?.name ?? String(localized: "The writing model"))
        }
        defer { restoreWhisper() }

        let prompt = stylePrompt(for: style, transcript: transcript, context: .quick, language: language)
        let swapStart = ContinuousClock.now
        writingModelState = .loading(firstTime: false)
        modelState = .idle
        try await coordinator.ensureLoaded(engine)
        writingModelState = .ready
        let swapTime = ContinuousClock.now - swapStart

        // Rough progress: light and moderate styles come back about as long as the transcript.
        let expected = Double(style.intensity == .heavy ? transcript.count / 2 : transcript.count)
        let output = try await engine.generate(
            instructions: prompt.instructions,
            input: prompt.input,
            maxTokens: prompt.maxTokens
        ) { text in
            let fraction = min(Double(text.count) / max(expected, 1), 0.97)
            Task { @MainActor in progress(fraction) }
        }
        Log.dictation.notice("Rewrite [\(style.name, privacy: .public)]: swap \(swapTime, privacy: .public), prompt \(output.promptTokens) tok at \(Int(output.promptTokensPerSecond)) tok/s, generated \(output.generatedTokens) tok at \(Int(output.generationTokensPerSecond)) tok/s")
        return OutputCleaner.clean(output.text)
    }

    /// After a rewrite: swap the writing model back out for Whisper so the next dictation streams live.
    func restoreWhisper() {
        writingModelState = .idle
        prepareModel()
    }
}
