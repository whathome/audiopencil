import APCore
import APModels
import APSummary
import AppKit

struct ProcessedLongForm {
    var body: String
    var title: String?
    /// Suggested tags already in the vault's tag list.
    var knownTags: [String]
    /// Suggested tags that would be new (need approval in the review).
    var newTags: [String]
}

/// Long recordings: rewrite in sections, then suggest a title and tags. One model swap for all of it.
extension AppModel {
    func processLongForm(
        transcript: String,
        style: Style,
        status: @escaping @MainActor (String) -> Void
    ) async -> ProcessedLongForm {
        let fallback = ProcessedLongForm(body: transcript, title: nil, knownTags: [], newTags: [])
        let engine = writing
        guard engine.isDownloaded else {
            Log.dictation.notice("Long-form: writing model not downloaded; keeping the transcript")
            return fallback
        }
        guard memoryPressure != .critical else { return fallback }
        defer { restoreWhisper() }

        do {
            status("Loading the writing model…")
            writingModelState = .loading(firstTime: false)
            modelState = .idle
            try await coordinator.ensureLoaded(engine)
            writingModelState = .ready

            var body = transcript
            if !style.isRaw {
                let vocabulary = settings.customVocabulary
                let sections = PromptBuilder.sections(of: transcript)
                if sections.count == 1 {
                    status("Writing the note…")
                    body = try await generateText(PromptBuilder.prompt(for: style, transcript: transcript, context: .longForm, vocabulary: vocabulary))
                } else if style.intensity == .heavy {
                    // Summaries: notes per section, then one note in the style from those.
                    var notes: [String] = []
                    for (index, section) in sections.enumerated() {
                        status("Summarising part \(index + 1) of \(sections.count)…")
                        notes.append(try await generateText(PromptBuilder.sectionNotesPrompt(section: section, index: index + 1, count: sections.count, vocabulary: vocabulary)))
                    }
                    status("Writing the note…")
                    body = try await generateText(PromptBuilder.prompt(for: style, transcript: notes.joined(separator: "\n\n"), context: .longForm, vocabulary: vocabulary))
                } else {
                    // Tidy or rewrite: section by section, kept in order.
                    var parts: [String] = []
                    for (index, section) in sections.enumerated() {
                        status("Writing part \(index + 1) of \(sections.count)…")
                        parts.append(try await generateText(PromptBuilder.prompt(for: style, transcript: section, context: .longForm, vocabulary: vocabulary)))
                    }
                    body = parts.joined(separator: "\n\n")
                }
                if body.isEmpty { body = transcript }
            }

            status("Suggesting a title and tags…")
            let answer = try await generateText(PromptBuilder.titleAndTagsPrompt(text: body, knownTags: tags))
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
