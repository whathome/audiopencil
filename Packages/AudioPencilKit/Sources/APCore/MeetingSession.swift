import Foundation

public struct MeetingSession: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case inPerson, videoCall
    }

    public enum Stage: String, Codable, Sendable {
        case recording, paused, saved, transcribing, writing, ready, failed
    }

    public struct Turn: Codable, Identifiable, Equatable, Sendable {
        public var id: UUID
        public var speaker: String
        public var start: Double
        public var end: Double
        public var text: String

        public init(speaker: String, start: Double, end: Double, text: String) {
            id = UUID()
            self.speaker = speaker
            self.start = start
            self.end = end
            self.text = text
        }
    }

    public var id: UUID
    public var title: String
    public var recorded: Date
    public var ended: Date?
    public var kind: Kind
    public var microphoneUID: String
    public var microphoneName: String
    public var applicationName: String?
    public var applicationBundleID: String?
    public var language: String
    public var speakerHint: Int?
    public var stage: Stage = .saved
    public var duration: Double = 0
    public var turns: [Turn] = []
    public var speakerNames: [String: String] = [:]
    public var summary: String = ""
    /// Editable Markdown tasks, kept separate from generated prose.
    public var actions: String = ""
    public var reviewed = false
    public var error: String?
    public var warnings: [String] = []
    public var notePath: String?
    public var filedMarkdown: String?
    public var audioPath: String?
    public var dailyNote = false
    public var processingRequested = false
    public var callAudioEnded = false
    public var retention: Note.Retention = .regular
    public var audioExpired = false

    public init(title: String, kind: Kind, microphoneUID: String, microphoneName: String, language: String) {
        id = UUID()
        recorded = Date()
        self.title = title
        self.kind = kind
        self.microphoneUID = microphoneUID
        self.microphoneName = microphoneName
        self.language = language
    }

    public func speakerName(_ id: String) -> String {
        speakerNames[id] ?? (id == "you" ? String(localized: "You", bundle: .module) : id)
    }

    public var transcript: String {
        turns.map { "\(speakerName($0.speaker)): \($0.text)" }.joined(separator: "\n\n")
    }

    public var canonicalTranscript: String {
        turns.map { "\($0.speaker == "you" ? String(localized: "You", bundle: .module) : $0.speaker): \($0.text)" }.joined(separator: "\n\n")
    }

    public var body: String {
        summary + (actions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n## " + String(localized: "Action items", bundle: .module) + "\n\n" + actions)
    }

    public func displayingSpeakerNames(in text: String) -> String {
        speakerNames.keys.sorted { $0.count > $1.count }.reduce(text) { result, id in
            let label = id == "you" ? String(localized: "You", bundle: .module) : id
            return result.replacingOccurrences(of: "\\b" + NSRegularExpression.escapedPattern(for: label) + "(?![\\w])", with: NSRegularExpression.escapedTemplate(for: speakerName(id)), options: .regularExpression)
        }
    }

    public var processing: Bool { stage == .transcribing || stage == .writing }
}

/// Matches only speakers whose turns overlap the previous window. New identities remain distinct
/// rather than pretending that a chunk-local "Speaker 1" is the same person throughout a meeting.
public enum MeetingSpeakerMatcher {
    public static func mapping(incoming: [MeetingSession.Turn], previous: [MeetingSession.Turn], before cutoff: Double) -> [String: String] {
        var weights: [String: [String: Double]] = [:]
        for turn in incoming where turn.start < cutoff {
            for prior in previous where prior.end > turn.start && prior.start < min(turn.end, cutoff) {
                let overlap = min(prior.end, turn.end, cutoff) - max(prior.start, turn.start)
                if overlap > 0 { weights[turn.speaker, default: [:]][prior.speaker, default: 0] += overlap }
            }
        }
        var matches: [String: String] = [:]
        var used: Set<String> = []
        let candidates = weights.flatMap { key, values in values.map { (incoming: key, previous: $0.key, weight: $0.value) } }
            .sorted { $0.weight > $1.weight }
        for candidate in candidates where matches[candidate.incoming] == nil && !used.contains(candidate.previous) {
            matches[candidate.incoming] = candidate.previous
            used.insert(candidate.previous)
        }
        return matches
    }
}

public enum MeetingSummaryParser {
    public static func split(_ text: String) -> (summary: String, actions: String)? {
        let lines = text.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).lowercased() == "## action items"
        }) else { return nil }
        let summary = lines[..<index].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return nil }
        return (summary, lines.dropFirst(index + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
