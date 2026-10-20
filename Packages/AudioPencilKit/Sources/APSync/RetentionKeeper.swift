import APCore
import APStorage
import Foundation

/// Applies the Retention board (PRD "Retention"): notes marked `delete` are deleted with their audio,
/// `archive` keeps everything forever, `regular` keeps the note but removes the audio after a year.
/// Deletions go to the trash (Nextcloud's trash bin, or the macOS Trash for a local vault).
///
/// Scans only the folders notes land in, and re-reads a file only when its ETag changes, so a check
/// costs one listing per folder when nothing moved.
public actor RetentionKeeper {
    public struct Report: Equatable, Sendable {
        public var deletedNotes: [String] = []
        public var expiredAudio: [String] = []
        public var backfilled: [String] = []
        /// Regular notes whose audio goes within `warningDays`, soonest first.
        public var expiringSoon: [Expiring] = []
        public var errors: [String] = []
    }

    public struct Expiring: Equatable, Sendable, Identifiable {
        public var notePath: String
        public var title: String
        public var expires: Date
        public var id: String { notePath }
    }

    struct Entry: Codable {
        var etag: String?
        var isAudioPencil: Bool
        var retention: String?
        var audio: String?
        var recorded: Date?
    }

    public static let audioLifetime: TimeInterval = 365 * 86_400
    public static let warningDays = 30

    private let stateURL: URL
    private var cache: [String: Entry]

    public init(stateURL: URL) {
        self.stateURL = stateURL
        cache = (try? JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: stateURL))) ?? [:]
    }

    public func run(
        provider: any StorageProvider,
        vaultPath: String,
        folders: [String],
        expireRegularAudio: Bool,
        now: Date = Date()
    ) async -> Report {
        self.vaultPath = vaultPath
        var report = Report()
        var seen = Set<String>()
        for folder in Set(folders) {
            await scan(StoragePath.join(vaultPath, folder), depth: 2, provider: provider, now: now, expire: expireRegularAudio, report: &report, seen: &seen)
        }
        cache = cache.filter { seen.contains($0.key) }
        save()
        report.expiringSoon.sort { $0.expires < $1.expires }
        return report
    }

    private func scan(_ folder: String, depth: Int, provider: any StorageProvider, now: Date, expire: Bool, report: inout Report, seen: inout Set<String>) async {
        guard let items = try? await provider.list(folder) else { return }
        for item in items where !item.isHidden {
            if item.isFolder {
                if depth > 0 { await scan(item.path, depth: depth - 1, provider: provider, now: now, expire: expire, report: &report, seen: &seen) }
                continue
            }
            guard item.name.hasSuffix(".md") else { continue }
            seen.insert(item.path)
            do {
                try await check(item, provider: provider, now: now, expire: expire, report: &report)
            } catch {
                report.errors.append("\(item.path): \(error.localizedDescription)")
            }
        }
    }

    private func check(_ item: StorageItem, provider: any StorageProvider, now: Date, expire: Bool, report: inout Report) async throws {
        var entry = cache[item.path]
        var text: String?
        var etag = item.etag

        if entry == nil || entry?.etag != item.etag || item.etag == nil {
            let (data, readEtag) = try await provider.read(item.path)
            let content = String(decoding: data, as: UTF8.self)
            text = content
            etag = readEtag ?? item.etag
            entry = Entry(
                etag: etag,
                isAudioPencil: NoteFrontmatter.string("type", in: content) == "audio-pencil",
                retention: NoteFrontmatter.string("retention", in: content),
                audio: NoteFrontmatter.string("audio", in: content),
                recorded: NoteFrontmatter.date("recorded", in: content)
            )
        }
        guard var entry, entry.isAudioPencil else {
            if let entry { cache[item.path] = entry }
            return
        }
        let audioPath = entry.audio.flatMap(NoteFrontmatter.linkTarget)
        let title = (item.name as NSString).deletingPathExtension

        switch Note.Retention(rawValue: entry.retention ?? "") {
        case .delete:
            if let audioPath { try await provider.delete(StoragePath.join(vaultPath, audioPath)) }
            try await provider.delete(item.path)
            cache[item.path] = nil
            report.deletedNotes.append(item.path)
            return

        case .archive:
            break

        case .regular, nil:
            let needsBackfill = entry.retention == nil
            var expiresNow = false
            if let audioPath, let recorded = entry.recorded {
                let expires = recorded.addingTimeInterval(Self.audioLifetime)
                if expire, expires <= now {
                    expiresNow = true
                } else if expires.timeIntervalSince(now) < Double(Self.warningDays) * 86_400 {
                    report.expiringSoon.append(Expiring(notePath: item.path, title: title, expires: expires))
                }
                _ = audioPath
            }
            guard needsBackfill || expiresNow else { break }

            var edited: String
            if let text { edited = text } else { edited = String(decoding: try await provider.read(item.path).data, as: UTF8.self) }
            if needsBackfill {
                // Notes from before the Retention board: mark them regular so they show up on it.
                edited = NoteFrontmatter.setting("retention", to: "regular", in: edited)
                report.backfilled.append(item.path)
            }
            if expiresNow, let audioPath {
                try await provider.delete(StoragePath.join(vaultPath, audioPath))
                edited = NoteFrontmatter.setting("audio", to: nil, in: edited)
                edited = NoteFrontmatter.setting("audio_expired", to: Self.day(now), in: edited)
                edited = NoteFrontmatter.removingEmbeds(of: audioPath, in: edited)
                entry.audio = nil
                report.expiredAudio.append(audioPath)
            }
            etag = try await provider.write(item.path, data: Data(edited.utf8), ifMatch: etag, createOnly: false)
            entry.retention = entry.retention ?? "regular"
        }
        entry.etag = etag
        cache[item.path] = entry
    }

    /// Vault folder of the current run: audio links in notes are relative to it.
    private var vaultPath = "/"

    private static func day(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    private func save() {
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: stateURL, options: .atomic) }
    }
}
