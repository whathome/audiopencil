import APAudio
import APCore
import APModels
import APStorage
import APTranscription
import AppKit
import SwiftUI
import UserNotifications

/// Turns dictations into vault notes (PRD "Vault layout"). Long recordings are filed straight away as
/// needs-review; reviewing happens on the Obsidian board.
@Observable
final class NoteMaker {
    static let defaultFolder = NoteFiling.defaultFolder
    static let recordingsFolder = NoteFiling.recordingsFolder

    private(set) var recent: [RecentNote] = []
    /// What long-form processing is doing right now, if anything.
    private(set) var processing: String?

    @ObservationIgnored private unowned let app: AppModel
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let notifications = NotificationDelegate()
    /// Meeting mode's speaker labels (small models, loaded only while labelling).
    @ObservationIgnored private let speakerLabeler = SpeakerLabeler()

    init(app: AppModel) {
        self.app = app
        folder = ModelLocations.root.deletingLastPathComponent().appending(path: "Pending", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        recent = (try? JSONDecoder().decode([RecentNote].self, from: Data(contentsOf: folder.appending(path: "recent.json")))) ?? []
        notifications.onOpen = { [weak self] path in
            if let url = self?.openURL(for: path) { NSWorkspace.shared.open(url) }
        }
        UNUserNotificationCenter.current().delegate = notifications
        fileLeftoverReviews()
    }

    /// Notes from before filing became immediate were held for a review window: file them as they were.
    private func fileLeftoverReviews() {
        let file = folder.appending(path: "pending.json")
        guard let leftovers = try? JSONDecoder().decode([PendingNote].self, from: Data(contentsOf: file)) else { return }
        try? FileManager.default.removeItem(at: file)
        for item in leftovers {
            var note = item.note
            note.tags += item.newTags.filter { !note.tags.contains($0) }
            let style = app.styles.first { $0.id == note.styleID }
            Task { await upload(note, audio: item.audioFile.map { folder.appending(path: $0) }, styleName: style?.displayName ?? note.styleID) }
        }
    }

    // MARK: Quick dictations

    /// "Save quick dictations": the delivered text as a note, no audio, no review.
    func saveQuick(_ capture: QuickCapture) {
        let style = capture.style
        let note = Note(
            title: NoteRenderer.fallbackTitle(from: capture.text),
            styleID: style.id,
            status: .reviewed,
            recorded: capture.recorded,
            duration: capture.duration,
            mode: .quick,
            folder: folder(for: style),
            language: capture.language.code,
            body: capture.text,
            transcript: keepsTranscript(style) ? capture.transcript : nil
        )
        Task { await upload(note, audio: nil, styleName: style.displayName) }
    }

    // MARK: Long-form

    func makeLongFormNote(_ capture: LongFormCapture) {
        let id = UUID()
        let audioName = "\(id.uuidString).m4a"
        let audioURL = folder.appending(path: audioName)
        processing = String(localized: "Saving the audio…")
        Task {
            let samples = capture.samples
            let savedAudio = await Task.detached(priority: .userInitiated) { () -> Bool in
                (try? AudioFileWriter.writeM4A(samples: samples, to: audioURL)) != nil
            }.value
            // Meeting: who said what, before writing. If labelling fails, it's filed as a plain note.
            var labelled: SpeakerTranscript?
            if capture.meeting {
                processing = String(localized: "Labelling the speakers…")
                do {
                    try await app.waitForSpeechModel()
                    labelled = try await speakerLabeler.transcribe(capture.samples, with: app.whisper, speakers: capture.speakers)
                } catch {
                    Log.dictation.error("Speaker labels failed: \(error.localizedDescription, privacy: .public)")
                }
                await speakerLabeler.unload()
            }
            let label = SpeakerTranscript.label
            let transcript = labelled?.text(label: label) ?? capture.transcript
            let result = await app.processLongForm(transcript: transcript, style: capture.style, language: capture.language, speakerLabel: labelled == nil ? nil : label) { [weak self] status in
                self?.processing = status
            }
            // Suggested tags are used as they are; new ones join the vault's tag list.
            let added = result.newTags.filter { !app.tags.contains($0) }
            if !added.isEmpty { app.tags += added }
            let note = Note(
                id: id,
                title: result.title ?? NoteRenderer.fallbackTitle(from: capture.transcript),
                styleID: capture.style.id,
                status: .needsReview,
                recorded: capture.recorded,
                duration: capture.duration,
                mode: labelled == nil ? .longForm : .meeting,
                tags: result.knownTags + added,
                folder: folder(for: capture.style),
                language: capture.language.code,
                // A meeting note that wasn't written up (raw, or no writing model) is the labelled transcript;
                // written ones keep it below.
                body: labelled.map { result.body == transcript ? $0.markdown(label: label) : result.body } ?? result.body,
                transcript: labelled.map { result.body == transcript ? nil : $0.markdown(label: label) } ?? (keepsTranscript(capture.style) ? capture.transcript : nil),
                speakers: labelled?.speakerCount
            )
            processing = String(localized: "Filing the note…")
            if let path = await upload(note, audio: savedAudio ? audioURL : nil, styleName: capture.style.displayName) {
                notifyFiled(note, path: path)
            }
            processing = nil
        }
    }

    // MARK: Upload

    @discardableResult
    private func upload(_ note: Note, audio: URL?, styleName: String) async -> String? {
        do {
            // Plain until the folder is known to be an Obsidian vault: standard Markdown reads everywhere,
            // Obsidian included.
            let filed = try await NoteFiling.queue(note, audio: audio, outbox: app.sync.outbox, layout: app.vault.layout ?? .plain)
            recent.insert(RecentNote(id: note.id, title: note.title, styleName: styleName, recorded: note.recorded, path: filed.path, status: note.status), at: 0)
            recent = Array(recent.prefix(50))
            saveRecent()
            Log.dictation.notice("Note queued: \(filed.path, privacy: .public)")
            app.sync.syncSoon(after: .zero)
            return filed.path
        } catch {
            Log.dictation.error("Couldn't queue the note: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Notification

    /// "Note filed": clicking opens it in Obsidian (or the file, for a plain folder on this Mac).
    private func notifyFiled(_ note: Note, path: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = app.vault.layout == .obsidian ? String(localized: "Note filed in Obsidian") : String(localized: "Note filed")
        content.body = note.title
        content.sound = .default
        content.userInfo = ["path": path]
        center.add(UNNotificationRequest(identifier: note.id.uuidString, content: content, trigger: nil))
    }

    // MARK: Helpers

    func folder(for style: Style) -> String {
        guard let folder = style.folder?.trimmingCharacters(in: .whitespaces), !folder.isEmpty else { return Self.defaultFolder }
        return StoragePath.join(folder)
    }

    /// Rewritten notes keep the raw transcript in a collapsed callout; tidy and raw ones don't need it.
    private func keepsTranscript(_ style: Style) -> Bool {
        !style.isRaw && style.intensity != .light
    }

    /// obsidian:// link to a note, assuming the Obsidian vault is named after its folder.
    /// Where "Open" goes for a note or file: Obsidian for a vault, the file itself for a plain folder on
    /// this Mac, nothing for a plain folder on a server.
    func openURL(for path: String) -> URL? {
        switch app.vault.layout {
        case .obsidian?: obsidianURL(for: path)
        default: app.vault.localFileURL(for: path)
        }
    }

    /// Keep forever or Delete, from the Notes page.
    func setRetention(_ value: Note.Retention, for note: RecentNote) {
        Task {
            guard await app.sync.setRetention(value, notePath: note.path) else { return }
            if value == .delete {
                recent.removeAll { $0.id == note.id }
            } else if let index = recent.firstIndex(where: { $0.id == note.id }) {
                recent[index].retention = value
            }
            saveRecent()
        }
    }

    func obsidianURL(for path: String) -> URL? {
        guard let vaultName = app.vault.vaultName else { return nil }
        var components = URLComponents(string: "obsidian://open")
        let file = path.hasPrefix("/") ? String(path.dropFirst()) : path
        components?.queryItems = [URLQueryItem(name: "vault", value: vaultName), URLQueryItem(name: "file", value: file)]
        return components?.url
    }

    private func saveRecent() {
        if let data = try? JSONEncoder().encode(recent) { try? data.write(to: folder.appending(path: "recent.json"), options: .atomic) }
    }
}

/// Shows banners while the app is active and opens the review when one is clicked.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: ((String) -> Void)?

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let path = response.notification.request.content.userInfo["path"] as? String else { return }
        await MainActor.run { self.onOpen?(path) }
    }
}
