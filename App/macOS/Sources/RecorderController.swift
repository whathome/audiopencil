import APAudio
import APCore
import APModels
import APStorage
import APTranscription
import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class RecorderController: NSObject, AVAudioPlayerDelegate {
    private(set) var recordings: [SavedRecording] = []
    var selectedID: UUID?
    private(set) var processingID: UUID?
    private(set) var progress: String?
    private(set) var isWorking = false
    var error: String?
    private(set) var playingID: UUID?
    private(set) var player: AVAudioPlayer?
    @ObservationIgnored private unowned let app: AppModel
    @ObservationIgnored private var store: RecordingStore?
    @ObservationIgnored private var job: Task<Void, Never>?

    var selected: SavedRecording? { recordings.first { $0.id == selectedID } }
    var interrupted: [SavedRecording] { recordings.filter { $0.status == .interrupted && $0.duration > 0 } }
    var isProcessing: Bool { isWorking }
    var root: URL { ModelLocations.root.deletingLastPathComponent().appending(path: "Recordings", directoryHint: .isDirectory) }

    init(app: AppModel) {
        self.app = app
        super.init()
        do {
            let store = try RecordingStore(root: root)
            self.store = store
            let snapshot = try store.load()
            recordings = snapshot.recordings
            if !snapshot.errors.isEmpty {
                report(String(localized: "Some recordings couldn't be loaded. Their audio is still in the recordings folder.") + "\n" + snapshot.errors.joined(separator: "\n"))
            }
        } catch { report(error.localizedDescription) }
    }

    func beginCapture(style: Style, language: SpokenLanguage, recorderOnly: Bool) throws -> RecordingWriter {
        stopPlayback()
        let store = try storage()
        let entry = try store.create(kind: recorderOnly ? .recorder : .dictation,
                                     title: String(localized: "Untitled recording"),
                                     language: language.code, styleID: style.id)
        do {
            let writer = try RecordingWriter(id: entry.id, url: store.audioURL(for: entry.id))
            recordings.insert(entry, at: 0)
            return writer
        } catch {
            try FileManager.default.removeItem(at: store.directory(for: entry.id))
            throw error
        }
    }

    @discardableResult
    func finishCapture(_ writer: RecordingWriter, interrupted: Bool = false) -> Bool {
        var failure: (any Error)?
        var writtenSeconds = writer.duration
        do { try writer.finish() } catch { failure = error }
        do {
            let store = try storage()
            guard var entry = recordings.first(where: { $0.id == writer.id }) else { throw RecordingStorageError.corruptAudio }
            entry.duration = try store.duration(for: writer.id)
            writtenSeconds = entry.duration
            if entry.duration == 0, failure == nil { failure = RecordingStorageError.empty }
            entry.status = interrupted || failure != nil ? .interrupted : .ready
            try update(entry)
            selectedID = entry.id
        } catch { failure = error }
        if let failure {
            if let index = recordings.firstIndex(where: { $0.id == writer.id }) {
                recordings[index].status = .interrupted
                recordings[index].duration = writtenSeconds
            }
            report(String(localized: "The recording couldn't finish saving. Any audio already written is kept for recovery.") + "\n" + failure.localizedDescription)
            return false
        }
        return true
    }

    @discardableResult
    func rememberText(id: UUID, transcript: String, body: String, style: Style, language: SpokenLanguage) -> Bool {
        guard var entry = recordings.first(where: { $0.id == id }) else {
            report(RecordingStorageError.corruptAudio.localizedDescription)
            return false
        }
        entry.transcript = transcript
        entry.body = body
        entry.language = language.code
        entry.styleID = style.id
        if entry.title == String(localized: "Untitled recording") { entry.title = NoteRenderer.fallbackTitle(from: transcript) }
        do { try update(entry); return true }
        catch { report(error.localizedDescription); return false }
    }

    func importAudio(_ url: URL) {
        guard canWork else { return }
        error = nil
        isWorking = true
        progress = String(localized: "Importing audio…")
        stopPlayback()
        job = Task {
            defer { finishWork() }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            var writer: RecordingWriter?
            var importedID: UUID?
            do {
                let store = try storage()
                let entry = try store.create(kind: .imported, title: url.deletingPathExtension().lastPathComponent,
                                             language: app.activeLanguage.code, styleID: Style.raw.id)
                importedID = entry.id
                recordings.insert(entry, at: 0)
                let output = try RecordingWriter(id: entry.id, url: store.audioURL(for: entry.id))
                writer = output
                try await Task.detached(priority: .userInitiated) {
                    try AudioFileReader.forEachMonoChunk(url) { try output.append($0) }
                }.value
                guard output.duration > 0 else { throw RecordingStorageError.empty }
                _ = finishCapture(output)
            } catch {
                Log.audio.error("Import failed: \(error.localizedDescription, privacy: .public)")
                if let writer { _ = finishCapture(writer, interrupted: true) }
                var message = String(localized: "Couldn't import the audio. Check that it plays in QuickTime Player and that this Mac has free space, then import it again. The source file wasn't changed.")
                if let importedID {
                    do { try discardEmptyImport(importedID) }
                    catch {
                        Log.audio.error("Couldn't remove the empty import: \(error.localizedDescription, privacy: .public)")
                        message += "\n" + String(localized: "The incomplete local copy couldn't be removed. Use Show in Finder to inspect it.")
                    }
                }
                report(message)
            }
        }
    }

    func chooseImport() {
        guard canWork else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importAudio(url)
    }

    func transcribe(_ id: UUID, style: Style, language: SpokenLanguage) {
        guard canWork, let entry = recordings.first(where: { $0.id == id }), entry.duration > 0 else { return }
        error = nil
        isWorking = true
        processingID = id
        progress = String(localized: "Loading the speech model…")
        stopPlayback()
        job = Task { [self] in
            var requestedModelLoad = false
            defer {
                finishWork()
                if requestedModelLoad { app.restoreWhisper() }
            }
            do {
                let store = try storage()
                // Finish any in-flight app model swap before acquiring the same residency coordinator.
                if let task = app.modelTask { _ = await task.result }
                try Task.checkCancellation()
                let engine = AppModel.engine(for: app.transcriptionVariant(for: language))
                guard engine.isDownloaded else { throw RecorderError.speechModelNotDownloaded }
                await engine.setLanguage(language.code)
                await engine.setVocabulary(app.settings.vocabulary(for: language))
                requestedModelLoad = true
                try await app.coordinator.ensureLoaded(engine)
                progress = String(localized: "Transcribing on this Mac…")
                let samples = try await Task.detached(priority: .userInitiated) { try store.samples(for: id) }.value
                try Task.checkCancellation()
                let heard = TranscriptCleaner.join(try await engine.transcribe(samples))
                try Task.checkCancellation()
                guard TranscriptCleaner.hasSpeech(heard) else { throw RecorderError.nothingHeard }
                guard rememberText(id: id, transcript: heard, body: heard, style: .raw, language: language) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let result = await app.processLongForm(transcript: heard, style: style, language: language, said: entry.recorded) { [weak self] status in
                    self?.progress = status
                }
                try Task.checkCancellation()
                guard var updated = recordings.first(where: { $0.id == id }) else { return }
                updated.transcript = heard
                updated.body = result.body
                updated.styleID = style.id
                updated.language = language.code
                updated.status = .ready
                updated.tags = result.knownTags + result.newTags
                if let title = result.title { updated.title = title }
                try update(updated)
                if let warning = result.warning { report(warning) }
                selectedID = id
            } catch is CancellationError {
                // The raw audio and any successfully transcribed text are already saved.
            } catch { report(error.localizedDescription) }
        }
    }

    func cancelProcessing() { job?.cancel() }

    func fileNote(_ id: UUID) {
        guard canWork, let entry = recordings.first(where: { $0.id == id }), entry.body != nil else { return }
        error = nil
        isWorking = true
        processingID = id
        progress = String(localized: "Filing the note…")
        job = Task {
            defer { finishWork() }
            do {
                let store = try storage()
                let audio = store.directory(for: id).appending(path: "filing.m4a")
                try await Task.detached(priority: .utility) { try store.export(id, to: audio, compressed: true) }.value
                try Task.checkCancellation()
                let path = try await app.notes.fileRecording(entry, audio: audio)
                var updated = entry
                updated.notePath = path
                try update(updated)
            } catch { report(error.localizedDescription) }
        }
    }

    func play(_ id: UUID) {
        if playingID == id, let player {
            if player.isPlaying { player.pause() }
            else if !player.play() { report(RecorderError.playback.localizedDescription) }
            return
        }
        guard canWork, let entry = recordings.first(where: { $0.id == id }), entry.duration > 0 else { return }
        error = nil
        stopPlayback()
        selectedID = id
        isWorking = true
        progress = String(localized: "Preparing playback…")
        job = Task {
            defer { finishWork() }
            do {
                let store = try storage()
                let url = store.directory(for: id).appending(path: "playback.caf")
                if !FileManager.default.fileExists(atPath: url.path) {
                    try await Task.detached(priority: .utility) { try store.export(id, to: url) }.value
                }
                let audio = try AVAudioPlayer(contentsOf: url)
                audio.enableRate = true
                audio.delegate = self
                #if DEBUG
                if ProcessInfo.processInfo.environment["AUDIOPENCIL_TEST_ROOT"] != nil { audio.volume = 0 }
                #endif
                guard audio.prepareToPlay(), audio.play() else { throw RecorderError.playback }
                player = audio
                playingID = id
            } catch { report(error.localizedDescription) }
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        playingID = nil
    }

    func seek(to seconds: Double) { player?.currentTime = seconds }
    func setSpeed(_ speed: Float) { player?.rate = speed }

    func export(_ id: UUID) {
        guard canWork, let entry = recordings.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.nameFieldStringValue = entry.title + ".m4a"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        isWorking = true
        progress = String(localized: "Exporting audio…")
        job = Task {
            defer { finishWork() }
            do {
                let store = try storage()
                try await Task.detached(priority: .utility) { try store.export(id, to: destination, compressed: true) }.value
            } catch { report(error.localizedDescription) }
        }
    }

    func delete(_ id: UUID) {
        guard canWork else { return }
        stopPlayback()
        do {
            try FileManager.default.trashItem(at: storage().directory(for: id), resultingItemURL: nil)
            recordings.removeAll { $0.id == id }
            if selectedID == id { selectedID = nil }
        } catch { report(error.localizedDescription) }
    }

    func report(_ message: String) {
        error = message
        Log.audio.error("\(message, privacy: .public)")
        AccessibilityNotification.Announcement(message).post()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.stopPlayback()
            if !flag { self?.report(String(localized: "Playback stopped unexpectedly. The saved audio is still available.")) }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let message = error?.localizedDescription ?? String(localized: "The audio couldn't be decoded.")
        Task { @MainActor [weak self] in self?.stopPlayback(); self?.report(message) }
    }

    private var canWork: Bool {
        !isWorking && !app.dictation.isActive && !app.meetings.ownsCapture && !app.meetings.isProcessing && app.notes.processing == nil
    }

    private func storage() throws -> RecordingStore {
        guard let store else { throw CocoaError(.fileWriteUnknown) }
        return store
    }

    private func discardEmptyImport(_ id: UUID) throws {
        let store = try storage()
        if FileManager.default.fileExists(atPath: store.audioURL(for: id).path),
           try store.duration(for: id) > 0 { return }
        try FileManager.default.removeItem(at: store.directory(for: id))
        recordings.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    private func update(_ entry: SavedRecording) throws {
        try storage().save(entry)
        guard let index = recordings.firstIndex(where: { $0.id == entry.id }) else { return }
        recordings[index] = entry
    }

    private func finishWork() {
        isWorking = false
        processingID = nil
        progress = nil
        job = nil
    }
}

private enum RecorderError: LocalizedError {
    case nothingHeard, playback, speechModelNotDownloaded
    var errorDescription: String? {
        switch self {
        case .nothingHeard: String(localized: "No speech was found. Your audio is kept; try another language or recording.")
        case .playback: String(localized: "The recording couldn't be played. Try exporting the saved audio.")
        case .speechModelNotDownloaded: String(localized: "Download the speech model in Settings › Models, then try again. Your saved audio is kept.")
        }
    }
}
