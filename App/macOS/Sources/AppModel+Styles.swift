import APCore
import APModels
import APSummary
import AppKit

/// Styles, per-app defaults and the MLX writing model.
extension AppModel {
    // MARK: Styles

    static func loadStyles() -> [Style] {
        guard let data = UserDefaults.standard.data(forKey: stylesKey),
              var saved = try? JSONDecoder().decode([Style].self, from: data)
        else { return Style.presets }
        // Presets added in later versions appear after the user's own list.
        for preset in Style.presets where !saved.contains(where: { $0.id == preset.id }) {
            saved.append(preset)
        }
        return saved
    }

    func saveStyles() {
        if let data = try? JSONEncoder().encode(styles) {
            UserDefaults.standard.set(data, forKey: Self.stylesKey)
        }
        applyPickerSettings()
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
        defer { restoreWhisper() }

        let prompt = PromptBuilder.prompt(for: style, transcript: transcript, context: .quick, vocabulary: settings.customVocabulary)
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
