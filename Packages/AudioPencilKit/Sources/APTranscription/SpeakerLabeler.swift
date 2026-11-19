import APCore
import APModels
import Foundation
import SpeakerKit

/// Meeting mode: works out who spoke when (pyannote, through Argmax SpeakerKit), and lines that up with
/// the speech model's word timings. The models are small (about 22 MB) and download on first use.
public actor SpeakerLabeler {
    public enum Stage: Sendable {
        case transcribing
        case labelling
    }

    private let root: URL
    private var kit: SpeakerKit?

    public init(root: URL = ModelLocations.root) {
        self.root = root
    }

    /// The whole recording with word timings, labelled by speaker. `speakers` nil works the number out.
    public func transcribe(
        _ samples: [Float],
        with engine: any TimedWordTranscribing,
        speakers: Int?,
        stage: @escaping @Sendable (Stage) -> Void = { _ in }
    ) async throws -> SpeakerTranscript {
        stage(.transcribing)
        let words = try await engine.transcribeTimedWords(samples)
        stage(.labelling)
        let spans = try await speakerSpans(samples, speakers: speakers)
        let transcript = SpeakerTranscript.align(words: words, spans: spans)
        Log.transcription.notice("Speaker labels: \(transcript.speakerCount) speakers, \(transcript.turns.count) turns, \(words.count) words")
        return transcript
    }

    /// Who spoke when.
    public func speakerSpans(_ samples: [Float], speakers: Int?) async throws -> [SpeakerSpan] {
        let kit = try await loadedKit()
        let result = try await kit.diarize(audioArray: samples, options: PyannoteDiarizationOptions(numberOfSpeakers: speakers))
        return result.segments.compactMap { segment in
            guard let speaker = segment.speaker.speakerId else { return nil }
            return SpeakerSpan(speaker: speaker, start: Double(segment.startTime), end: Double(segment.endTime))
        }
    }

    public func unload() async {
        await kit?.unloadModels()
        kit = nil
    }

    private func loadedKit() async throws -> SpeakerKit {
        if let kit { return kit }
        let kit = try await SpeakerKit(PyannoteConfig(downloadBase: root.path, verbose: false, logLevel: .error))
        self.kit = kit
        return kit
    }
}
