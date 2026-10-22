import APCore
import APStorage
import APSync
import Foundation

/// A line waiting to be added to a vault file: a note's link in that day's daily note, or a push-to-talk
/// line in the daily note or a chosen file. Kept on this device until it's written, so it survives being
/// offline and restarts.
struct PendingAppend: Codable, Identifiable, Equatable {
    enum Target: Codable, Equatable {
        /// The daily note for this day (the day of the recording, not of the upload).
        case dailyNote(Date)
        /// A vault-relative file, e.g. "Inbox.md".
        case file(String)
    }

    var id = UUID()
    var target: Target
    var entry: String
    /// "## Audio Pencil"; nil or blank adds at the end.
    var heading: String?
}

/// Where Daily notes stands in the vault, for settings and the recording controls.
enum DailyNotesAvailability: Equatable {
    /// Not checked yet (no storage, or the first sync hasn't run).
    case unknown
    /// The storage isn't an Obsidian vault, or Obsidian's Daily notes plugin is off.
    case off
    case on
}

/// The append queue: reads the file, adds the line, writes it back only if nothing changed in between
/// (retrying if Obsidian saved first), and creates a missing daily note from its template.
actor AppendQueue {
    private let url: URL
    private(set) var items: [PendingAppend]

    init(url: URL) {
        self.url = url
        items = (try? JSONDecoder().decode([PendingAppend].self, from: Data(contentsOf: url))) ?? []
    }

    func add(_ item: PendingAppend) {
        items.append(item)
        save()
    }

    /// Writes what it can, oldest first; anything that fails stays for the next sync.
    func flush(to provider: any StorageProvider, vaultPath: String, daily: DailyNotesSetup?) async {
        var remaining: [PendingAppend] = []
        for item in items {
            do {
                try await write(item, provider: provider, vaultPath: vaultPath, daily: daily)
            } catch {
                Log.models.error("Couldn't add to a note yet: \(error.localizedDescription, privacy: .public)")
                remaining.append(item)
            }
        }
        items = remaining
        save()
    }

    private func write(_ item: PendingAppend, provider: any StorageProvider, vaultPath: String, daily: DailyNotesSetup?) async throws {
        let path: String
        var blank = ""
        switch item.target {
        case .dailyNote(let date):
            guard let daily else { throw StorageError.notFound(String(localized: "Daily notes is off in Obsidian")) }
            let relative = daily.path(for: date)
            path = StoragePath.join(vaultPath, relative)
            if let template = daily.templatePath, let data = try? await provider.read(StoragePath.join(vaultPath, template)).data {
                let title = String((relative as NSString).lastPathComponent.dropLast(3))
                blank = DailyTemplate.fill(String(decoding: data, as: UTF8.self), title: title, date: date)
            }
        case .file(let file):
            let relative = file.hasSuffix(".md") ? file : file + ".md"
            path = StoragePath.join(vaultPath, relative)
        }
        for _ in 0..<3 {
            do {
                if try await provider.item(at: path) == nil {
                    try await provider.createFolder(StoragePath.parent(of: path))
                    let text = NoteAppend.apply(item.entry, to: blank, heading: item.heading)
                    _ = try await provider.write(path, data: Data(text.utf8), ifMatch: nil, createOnly: true)
                } else {
                    let (data, etag) = try await provider.read(path)
                    let text = NoteAppend.apply(item.entry, to: String(decoding: data, as: UTF8.self), heading: item.heading)
                    _ = try await provider.write(path, data: Data(text.utf8), ifMatch: etag, createOnly: false)
                }
                Log.models.notice("Added a line to \(path, privacy: .public)")
                return
            } catch StorageError.conflict {
                continue // changed (or created) in between: read it again
            }
        }
        throw StorageError.conflict(path)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: url, options: .atomic) }
    }
}

/// A note's line in the daily note.
enum DailyNoteEntry {
    /// "- 14:32 [[Audio Pencil/Notes/2026-10-21 1432 Title|Title]]", or "![[…]]" to embed it.
    static func line(for note: Note, path: String, embed: Bool) -> String {
        var target = path.hasPrefix("/") ? String(path.dropFirst()) : path
        if target.hasSuffix(".md") { target = String(target.dropLast(3)) }
        if embed { return "![[\(target)]]" }
        return "- \(clock(note.recorded)) [[\(target)|\(note.title)]]"
    }

    /// "14:32", always 24-hour.
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
