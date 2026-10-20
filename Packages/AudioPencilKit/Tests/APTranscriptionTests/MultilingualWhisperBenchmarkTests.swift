import APCore
import APModels
import APTranscription
import Foundation
import Testing

/// Opt-in benchmark of multilingual Whisper models on this Mac, on French, Spanish and German speech from
/// the system voices. Downloads each model (0.5–0.6 GB) into the app's model folder:
///   AUDIOPENCIL_WHISPER_BENCH=1 AUDIOPENCIL_WHISPER_BENCH_OUT=$PWD/../../docs/benchmarks/multilingual-whisper.md \
///   swift test --filter MultilingualWhisperBenchmark
/// AUDIOPENCIL_WHISPER_BENCH_MODELS (comma-separated) overrides the candidates.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AUDIOPENCIL_WHISPER_BENCH"] == "1"), .serialized)
struct MultilingualWhisperBenchmarkTests {
    static let candidates = [
        "openai_whisper-small",
        "openai_whisper-large-v3-v20240930_turbo_632MB",
    ]

    struct Clip {
        let language: String
        let voice: String
        let script: String
    }

    static let clips = [
        Clip(language: "fr", voice: "Flo (French (France))", script: """
            Petit point sur la sauvegarde du chalet. Aujourd'hui, je sauvegarde le serveur de la maison chaque nuit \
            sur un disque externe dans la même pièce, ce qui ne sert à rien en cas d'inondation. Ce week-end, je vais \
            mettre en place des sauvegardes chiffrées vers le serveur du chalet. Je dois demander une adresse IP fixe \
            à Dave avant samedi, et je testerai une restauration complète dimanche.
            """),
        Clip(language: "es", voice: "Flo (Spanish (Spain))", script: """
            Una actualización rápida sobre la copia de seguridad de la casa de campo. Ahora mismo hago una copia del \
            servidor cada noche en un disco externo en la misma habitación, lo que no sirve de nada si hay una \
            inundación. Este fin de semana voy a configurar copias cifradas al servidor de la casa de campo. Tengo que \
            pedirle a Dave una dirección IP fija antes del sábado y probaré una restauración completa el domingo.
            """),
        Clip(language: "de", voice: "Anna", script: """
            Kurzes Update zur Datensicherung im Ferienhaus. Im Moment sichere ich den Server jede Nacht auf eine \
            externe Festplatte im selben Raum, was bei einem Hochwasser nichts nützt. Am Wochenende richte ich \
            verschlüsselte Sicherungen auf den Server im Ferienhaus ein. Ich muss Dave vor Samstag um eine feste \
            IP-Adresse bitten und teste am Sonntag eine vollständige Wiederherstellung.
            """),
    ]

    @Test func compareMultilingualModels() async throws {
        let environment = ProcessInfo.processInfo.environment
        let variants = environment["AUDIOPENCIL_WHISPER_BENCH_MODELS"]?.split(separator: ",").map(String.init) ?? Self.candidates
        let audio = try Self.clips.map { clip in (clip, try WhisperIntegrationTests.synthesise(clip.script, voice: clip.voice)) }
        var rows: [String] = []
        let coordinator = ModelCoordinator()

        for variant in variants {
            let engine = WhisperEngine(variant: variant)
            if !engine.isDownloaded { try await engine.download { _ in } }
            let firstTime = engine.needsFirstTimePreparation
            let loadStart = ContinuousClock.now
            try await coordinator.ensureLoaded(engine)
            let load = Self.seconds(ContinuousClock.now - loadStart)
            let footprint = MemoryFootprint.formatted(MemoryFootprint.currentBytes())
            print("[whisper-bench] \(variant): load \(load) s (first time: \(firstTime)), footprint \(footprint)")

            for (clip, samples) in audio {
                await engine.setLanguage(clip.language)
                // As in the app: passes while the audio arrives in real-time-sized chunks, then the tail at stop.
                let source = GrowingSource()
                let streamer = StreamingTranscriber(engine: engine, source: source)
                let chunk = 16_000 / 2
                var index = 0
                let streamStart = ContinuousClock.now
                while index < samples.count {
                    source.append(Array(samples[index..<min(index + chunk, samples.count)]))
                    index += chunk
                    await streamer.passIfNeeded()
                }
                let streaming = Self.seconds(ContinuousClock.now - streamStart)
                let finishStart = ContinuousClock.now
                let text = try await streamer.finish()
                let finish = Self.seconds(ContinuousClock.now - finishStart)
                let duration = Double(samples.count) / 16_000
                let wer = WordErrorRate.compute(reference: clip.script, hypothesis: text)
                print("[whisper-bench] \(variant) \(clip.language): WER \(Int(wer * 100))%, passes \(streaming) s for \(Int(duration)) s audio, stop→text \(finish) s")
                print("[whisper-bench] text: \(text)")
                rows.append("| \(variant) | \(clip.language) | \(Int((wer * 100).rounded()))% | \(String(format: "%.1f", streaming)) s / \(Int(duration)) s | \(String(format: "%.2f", finish)) s | \(firstTime ? "\(load) s (first)" : "\(load) s") | \(footprint) |")
                rows.append("| | | _\(text.replacingOccurrences(of: "|", with: "/"))_ | | | | |")
            }
            await coordinator.unload(engine)
        }

        if let out = environment["AUDIOPENCIL_WHISPER_BENCH_OUT"] {
            let table = """
                | Model | Lang | WER | Live passes / audio | Stop → text | Load | Footprint |
                |---|---|---|---|---|---|---|
                \(rows.joined(separator: "\n"))
                """
            try table.write(toFile: out, atomically: true, encoding: .utf8)
        }
    }

    static func seconds(_ duration: Duration) -> Double {
        (Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18).rounded(toPlaces: 2)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
