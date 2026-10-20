import APAudio
import APCore
import APModels
import APStorage
import AppKit
import SwiftUI
import UserNotifications

/// A long-form note waiting for review. Kept on this Mac (with its audio) until approved or skipped.
struct PendingNote: Codable, Identifiable, Equatable {
    var note: Note
    /// Suggested tags that aren't in the vault's tag list yet.
    var newTags: [String]
    /// Audio file name in the pending folder.
    var audioFile: String?
    var id: UUID { note.id }
}

/// A note handed to the upload queue, for the Notes page.
struct RecentNote: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var styleName: String
    var recorded: Date
    var path: String
    var status: Note.Status
}

/// Turns dictations into vault notes (PRD "Vault layout", "Review flow").
@Observable
final class NoteMaker {
    static let defaultFolder = "/Audio Pencil/Notes"
    static let recordingsFolder = "/Audio Pencil/Recordings"

    private(set) var pending: [PendingNote] = []
    private(set) var recent: [RecentNote] = []
    /// What long-form processing is doing right now, if anything.
    private(set) var processing: String?

    @ObservationIgnored private unowned let app: AppModel
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let notifications = NotificationDelegate()
    @ObservationIgnored private var reviewWindow: NSWindow?

    init(app: AppModel) {
        self.app = app
        folder = ModelLocations.root.deletingLastPathComponent().appending(path: "Pending", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        pending = (try? JSONDecoder().decode([PendingNote].self, from: Data(contentsOf: folder.appending(path: "pending.json")))) ?? []
        recent = (try? JSONDecoder().decode([RecentNote].self, from: Data(contentsOf: folder.appending(path: "recent.json")))) ?? []
        notifications.onOpen = { [weak self] id in self?.review(id: id) }
        UNUserNotificationCenter.current().delegate = notifications
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
            body: capture.text,
            transcript: keepsTranscript(style) ? capture.transcript : nil
        )
        Task { await upload(note, audio: nil, styleName: style.name) }
    }

    // MARK: Long-form

    func makeLongFormNote(_ capture: LongFormCapture) {
        let id = UUID()
        let audioName = "\(id.uuidString).m4a"
        let audioURL = folder.appending(path: audioName)
        processing = "Saving the audio…"
        Task {
            let samples = capture.samples
            let savedAudio = await Task.detached(priority: .userInitiated) { () -> Bool in
                (try? AudioFileWriter.writeM4A(samples: samples, to: audioURL)) != nil
            }.value
            let result = await app.processLongForm(transcript: capture.transcript, style: capture.style) { [weak self] status in
                self?.processing = status
            }
            let note = Note(
                id: id,
                title: result.title ?? NoteRenderer.fallbackTitle(from: capture.transcript),
                styleID: capture.style.id,
                status: .needsReview,
                recorded: capture.recorded,
                duration: capture.duration,
                mode: .longForm,
                tags: result.knownTags,
                folder: folder(for: capture.style),
                body: result.body,
                transcript: keepsTranscript(capture.style) ? capture.transcript : nil
            )
            pending.append(PendingNote(note: note, newTags: result.newTags, audioFile: savedAudio ? audioName : nil))
            savePending()
            processing = nil
            notifyReady(note)
        }
    }

    /// Approve: status `reviewed`, with the title, tags and folder as edited. New tags join the vault's list.
    func approve(_ item: PendingNote, title: String, tags: [String], folder: String) {
        var note = item.note
        note.title = title.isEmpty ? note.title : title
        note.tags = tags
        note.folder = folder
        note.status = .reviewed
        let added = tags.filter { !app.tags.contains($0) }
        if !added.isEmpty { app.tags += added }
        finish(item, as: note)
    }

    /// Skip: upload as suggested with status `needs-review` (only tags already in the vault's list).
    func skip(_ item: PendingNote) {
        finish(item, as: item.note)
    }

    private func finish(_ item: PendingNote, as note: Note) {
        pending.removeAll { $0.id == item.id }
        savePending()
        closeReviewIfShowing(item.id)
        let audio = item.audioFile.map { folder.appending(path: $0) }
        let style = app.styles.first { $0.id == note.styleID }
        Task { await upload(note, audio: audio, styleName: style?.name ?? note.styleID) }
    }

    // MARK: Upload

    private func upload(_ note: Note, audio: URL?, styleName: String) async {
        var note = note
        let base = NoteRenderer.baseName(for: note)
        do {
            if let audio, let data = try? Data(contentsOf: audio) {
                let path = StoragePath.join(Self.recordingsFolder, base + ".m4a")
                note.audioPath = path
                try await app.sync.outbox.enqueue(path: path, data: data)
                try? FileManager.default.removeItem(at: audio)
            }
            let path = NoteRenderer.notePath(for: note)
            try await app.sync.outbox.enqueue(path: path, data: Data(NoteRenderer.markdown(for: note).utf8))
            recent.insert(RecentNote(id: note.id, title: note.title, styleName: styleName, recorded: note.recorded, path: path, status: note.status), at: 0)
            recent = Array(recent.prefix(50))
            saveRecent()
            Log.dictation.notice("Note queued: \(path, privacy: .public)")
            app.sync.syncSoon(after: .zero)
        } catch {
            Log.dictation.error("Couldn't queue the note: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Review

    func review(id: UUID? = nil) {
        guard let item = id.flatMap({ id in pending.first { $0.id == id } }) ?? pending.first else { return }
        if reviewWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "Review note"
            reviewWindow = window
        }
        reviewWindow?.contentView = NSHostingView(rootView: ReviewView(maker: self, item: item, knownTags: app.tags).id(item.id))
        reviewWindow?.center()
        NSApp.activate()
        reviewWindow?.makeKeyAndOrderFront(nil)
    }

    private func closeReviewIfShowing(_ id: UUID) {
        guard reviewWindow?.isVisible == true else { return }
        if let next = pending.first {
            review(id: next.id)
        } else {
            reviewWindow?.orderOut(nil)
        }
    }

    private func notifyReady(_ note: Note) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "Note ready to review"
        content.body = note.title
        content.sound = .default
        content.userInfo = ["id": note.id.uuidString]
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
    func obsidianURL(for path: String) -> URL? {
        guard let vaultName = app.vault.vaultName else { return nil }
        var components = URLComponents(string: "obsidian://open")
        let file = path.hasPrefix("/") ? String(path.dropFirst()) : path
        components?.queryItems = [URLQueryItem(name: "vault", value: vaultName), URLQueryItem(name: "file", value: file)]
        return components?.url
    }

    private func savePending() {
        if let data = try? JSONEncoder().encode(pending) { try? data.write(to: folder.appending(path: "pending.json"), options: .atomic) }
    }

    private func saveRecent() {
        if let data = try? JSONEncoder().encode(recent) { try? data.write(to: folder.appending(path: "recent.json"), options: .atomic) }
    }
}

/// Shows banners while the app is active and opens the review when one is clicked.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: ((UUID) -> Void)?

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = (response.notification.request.content.userInfo["id"] as? String).flatMap(UUID.init) else { return }
        await MainActor.run { self.onOpen?(id) }
    }
}
