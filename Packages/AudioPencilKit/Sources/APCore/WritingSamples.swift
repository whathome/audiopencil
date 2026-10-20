import Foundation

/// A piece of the user's own writing, used as an example by the "Like me" style (few-shot, no fine-tuning).
public struct WritingSample: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    /// Type of writing, e.g. "work-email" or "diary" (PRD: each answer is labelled with its type).
    public var kind: String
    public var text: String
    /// Interview prompt this answers, if any.
    public var promptID: String?
    /// Whisper code of the language it's written in; nil for samples from before languages (English).
    public var language: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, text, language
        case promptID = "prompt"
    }

    public init(id: String = UUID().uuidString.prefix(8).lowercased(), kind: String, text: String, promptID: String? = nil, language: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.promptID = promptID
        self.language = language
    }

    public var spokenLanguage: SpokenLanguage { SpokenLanguage(code: language ?? "en") }

    public var wordCount: Int { UsageStats.wordCount(text) }
}

/// PRD starter interview: typed answers of 100 to 300 words, written the way the user normally writes.
public struct InterviewPrompt: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: String
    public let title: String
    public let prompt: String

    public static let wordRange = 100...300

    public static let all: [InterviewPrompt] = [
        .init(id: "work-email", kind: "work-email", title: "Work email", prompt: "Tell a colleague or client that something is running late, why, and what happens next."),
        .init(id: "technical", kind: "technical-explanation", title: "Technical explanation", prompt: "Explain to a smart, non-technical friend why you run your own server instead of using cloud services."),
        .init(id: "instructions", kind: "instructions", title: "Instructions", prompt: "Write step-by-step instructions for a task you know well, around the house or on a computer."),
        .init(id: "opinion", kind: "opinion", title: "Opinion", prompt: "Pick a tool, product or habit you feel strongly about and argue for or against it."),
        .init(id: "problem-story", kind: "problem-story", title: "Problem story", prompt: "Describe something that broke or went wrong recently and how you worked it out."),
        .init(id: "diary", kind: "diary", title: "Diary", prompt: "Write a few honest paragraphs about how today actually went."),
        .init(id: "decision", kind: "decision", title: "Decision", prompt: "Lay out a decision you're weighing, the options, and which way you're leaning."),
        .init(id: "short-messages", kind: "short-messages", title: "Short messages", prompt: "Write three quick texts: making plans, turning something down, and thanking someone."),
        .init(id: "feedback", kind: "feedback", title: "Feedback", prompt: "Give honest feedback on someone's idea or piece of work, kind but direct."),
        .init(id: "place", kind: "place", title: "Place", prompt: "Describe a place you know well to someone who has never been there."),
        .init(id: "recap", kind: "recap", title: "Recap", prompt: "Summarise a recent conversation or meeting for someone who missed it."),
    ]

    /// Kinds for samples added outside the interview.
    public static let kinds = all.map(\.kind) + ["other"]

    /// Minimum samples before "Like me" is worth using.
    public static let minimumSamples = 3
}

/// Picks the samples closest to what's being written, so the examples match the kind of note.
public enum WritingSampleSelector {
    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "to", "of", "in", "on", "for", "with", "at", "by", "from", "is", "it",
        "that", "this", "was", "be", "are", "i", "you", "we", "they", "he", "she", "my", "your", "our", "so", "just",
        "like", "um", "uh", "as", "if", "then", "there", "have", "has", "had", "do", "did", "not", "me", "what", "about",
    ]

    /// Kinds that tend to match a few strong cue words in the transcript.
    private static let cues: [String: [String]] = [
        "diary": ["today", "tonight", "morning", "felt", "tired", "kids"],
        "work-email": ["client", "deadline", "late", "delay", "update", "email"],
        "recap": ["meeting", "call", "agreed", "decided", "discussed"],
        "decision": ["options", "deciding", "leaning", "choose", "whether"],
        "instructions": ["step", "first", "then", "click", "open"],
        "problem-story": ["broke", "broken", "fixed", "error", "problem", "worked out"],
        "short-messages": ["text", "message", "thanks", "tomorrow"],
        "feedback": ["feedback", "suggest", "liked", "improve"],
    ]

    /// Up to `limit` samples, most similar first, within `wordBudget` words in total. With a `language`,
    /// samples written in it come first; others only fill the gap when there aren't enough.
    public static func pick(for text: String, from samples: [WritingSample], language: SpokenLanguage? = nil, limit: Int = 2, wordBudget: Int = 450) -> [WritingSample] {
        let target = vector(text)
        let lowered = text.lowercased()
        let scored = samples.filter { $0.wordCount > 0 }.map { sample -> (WritingSample, Double) in
            var score = cosine(target, vector(sample.text))
            if let language, sample.spokenLanguage == language { score += 10 } // outranks any similarity
            let hits = cues[sample.kind, default: []].filter { lowered.contains($0) }.count
            score += 0.05 * Double(min(hits, 3))
            return (sample, score)
        }
        .sorted { $0.1 > $1.1 }

        var chosen: [WritingSample] = []
        var words = 0
        for (sample, _) in scored where chosen.count < limit {
            let count = sample.wordCount
            if words + count > wordBudget { continue }
            chosen.append(sample)
            words += count
        }
        if chosen.isEmpty, let first = scored.first?.0 {
            chosen = [WritingSample(id: first.id, kind: first.kind, text: first.text.split(separator: " ").prefix(wordBudget).joined(separator: " "), promptID: first.promptID)]
        }
        return chosen
    }

    static func vector(_ text: String) -> [String: Double] {
        var counts: [String: Double] = [:]
        for word in text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }) {
            let token = String(word)
            guard token.count > 2, !stopWords.contains(token) else { continue }
            counts[token, default: 0] += 1
        }
        return counts
    }

    static func cosine(_ a: [String: Double], _ b: [String: Double]) -> Double {
        let dot = a.reduce(0.0) { $0 + $1.value * (b[$1.key] ?? 0) }
        let normA = a.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        let normB = b.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return normA > 0 && normB > 0 ? dot / (normA * normB) : 0
    }
}

extension PromptBuilder {
    /// "Like me": the style prompt plus the user's closest writing samples as examples of voice.
    public static func prompt(for style: Style, transcript: String, context: Context, vocabulary: [String], language: SpokenLanguage = .english, examples: [WritingSample]) -> StylePrompt {
        var prompt = prompt(for: style, transcript: transcript, context: context, vocabulary: vocabulary, language: language)
        guard !examples.isEmpty else { return prompt }
        let blocks = examples.map { "<example kind=\"\($0.kind)\">\n\($0.text)\n</example>" }.joined(separator: "\n")
        prompt.instructions += """


            Examples of how I write. Match their voice: word choice, sentence length, punctuation, tone. \
            Don't copy their content.
            \(blocks)
            """
        return prompt
    }
}
