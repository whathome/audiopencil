import APCore
import APModels
import APSummary
import Foundation

enum RewriteError: LocalizedError {
    case modelNotDownloaded
    case lowMemory
    case languageUnsupported(language: String, model: String)

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded: String(localized: "The writing model isn't downloaded yet")
        case .lowMemory: String(localized: "Memory is low")
        case .languageUnsupported(let language, let model): String(localized: "\(model) can't write \(language)")
        }
    }
}

struct ProcessedLongForm {
    var body: String
    var title: String?
    /// Suggested tags already in the vault's tag list.
    var knownTags: [String]
    /// Suggested tags that would be new (need approval in the review).
    var newTags: [String]
}

/// Where a model is: shared by the speech and writing models on both platforms.
enum TranscriptionModelState: Equatable {
    case idle
    case downloading(Double)
    case loading(firstTime: Bool)
    case ready
    case failed(String)
}

/// What writing in styles needs from the app (the Mac's AppModel, the iPhone's PhoneModel).
protocol WritingHost: AnyObject {
    var writing: SummaryEngine { get }
    var settings: DictationSettings { get }
    var tags: [String] { get }
    var writingSamples: [WritingSample] { get }
    var memoryPressure: MemoryPressureMonitor.Level { get }
    var coordinator: ModelCoordinator { get }
    var writingModelState: TranscriptionModelState { get set }
    /// The writing model is about to take the speech model's place in memory.
    func speechModelWillUnload()
    /// Writing's done: bring the speech model back.
    func restoreWhisper()
}

extension WritingHost {
    /// Whether the current writing model can write `language`; if not, styles keep the raw transcript.
    func canStyle(in language: SpokenLanguage) -> Bool {
        WritingLanguages.canWrite(language.code, withModel: settings.writingModel)
    }

    /// Style prompt, with the closest writing samples for "Like me". `speakerLabel`: a meeting transcript
    /// labelled "Speaker 1: …" (no "Like me" imitation then: it's not one person writing).
    func stylePrompt(for style: Style, transcript: String, context: PromptBuilder.Context, language: SpokenLanguage, speakerLabel: String? = nil) -> StylePrompt {
        let vocabulary = settings.vocabulary(for: language)
        guard style.tone == .likeMe, speakerLabel == nil else {
            return PromptBuilder.prompt(for: style, transcript: transcript, context: context, vocabulary: vocabulary, language: language, speakerLabel: speakerLabel)
        }
        let examples = WritingSampleSelector.pick(for: transcript, from: writingSamples, language: language)
        return PromptBuilder.prompt(for: style, transcript: transcript, context: context, vocabulary: vocabulary, language: language, examples: examples)
    }
}

/// Long recordings: rewrite in sections, then suggest a title and tags. One model swap for all of it.
extension WritingHost {
    func processLongForm(
        transcript: String,
        style: Style,
        language: SpokenLanguage,
        speakerLabel: String? = nil,
        said: Date = Date(),
        status: @escaping @MainActor (String) -> Void
    ) async -> ProcessedLongForm {
        let fallback = ProcessedLongForm(body: transcript, title: nil, knownTags: [], newTags: [])
        let engine = writing
        guard engine.isDownloaded else {
            Log.dictation.notice("Long-form: writing model not downloaded; keeping the transcript")
            return fallback
        }
        guard memoryPressure != .critical else { return fallback }
        guard canStyle(in: language) else {
            Log.dictation.notice("Long-form: \(self.settings.writingModel, privacy: .public) can't write \(language.code, privacy: .public); keeping the transcript")
            return fallback
        }
        defer { restoreWhisper() }

        do {
            status(String(localized: "Loading the writing model…"))
            writingModelState = .loading(firstTime: false)
            speechModelWillUnload()
            try await coordinator.ensureLoaded(engine)
            writingModelState = .ready

            var body = transcript
            if !style.isRaw {
                let vocabulary = settings.vocabulary(for: language)
                // A meeting splits between turns, so every part keeps its speaker labels.
                let sections = speakerLabel == nil ? PromptBuilder.sections(of: transcript) : PromptBuilder.sections(ofTurns: transcript)
                if sections.count == 1 {
                    status(String(localized: "Writing the note…"))
                    body = try await generateText(stylePrompt(for: style, transcript: transcript, context: .longForm, language: language, speakerLabel: speakerLabel))
                } else if style.intensity == .heavy {
                    // Summaries: notes per section, then one note in the style from those.
                    var notes: [String] = []
                    for (index, section) in sections.enumerated() {
                        status(String(localized: "Summarising part \(index + 1) of \(sections.count)…"))
                        notes.append(try await generateText(PromptBuilder.sectionNotesPrompt(section: section, index: index + 1, count: sections.count, vocabulary: vocabulary, language: language, speakerLabel: speakerLabel)))
                    }
                    status(String(localized: "Writing the note…"))
                    body = try await generateText(stylePrompt(for: style, transcript: PromptBuilder.joinSectionNotes(notes), context: .sectionNotes(count: notes.count), language: language, speakerLabel: speakerLabel))
                } else {
                    // Tidy or rewrite: section by section, kept in order.
                    var parts: [String] = []
                    for (index, section) in sections.enumerated() {
                        status(String(localized: "Writing part \(index + 1) of \(sections.count)…"))
                        parts.append(try await generateText(stylePrompt(for: style, transcript: section, context: .longForm, language: language, speakerLabel: speakerLabel)))
                    }
                    body = parts.joined(separator: "\n\n")
                }
                if body.isEmpty { body = transcript }
                // Action items as Obsidian tasks, with the dates that were said ("by Friday" → 📅).
                if style.extractActionItems, body != transcript {
                    body = ActionItems.asTasks(body, said: said, language: language.code)
                }
            }

            status(String(localized: "Suggesting a title and tags…"))
            let answer = try await generateText(PromptBuilder.titleAndTagsPrompt(text: body, knownTags: tags, language: language))
            let suggestion = TitleAndTags.parse(answer)
            return ProcessedLongForm(
                body: body,
                title: suggestion.title,
                knownTags: suggestion.tags.filter { tags.contains($0) },
                newTags: suggestion.tags.filter { !tags.contains($0) }
            )
        } catch {
            Log.dictation.error("Long-form processing failed: \(error.localizedDescription, privacy: .public)")
            return fallback
        }
    }

    private func generateText(_ prompt: StylePrompt) async throws -> String {
        let output = try await writing.generate(instructions: prompt.instructions, input: prompt.input, maxTokens: prompt.maxTokens)
        Log.dictation.notice("Long-form step: prompt \(output.promptTokens) tok, generated \(output.generatedTokens) tok at \(Int(output.generationTokensPerSecond)) tok/s")
        return OutputCleaner.clean(output.text)
    }
}
