import APCore
import APStorage
import Foundation

/// Offline-first upload queue (PRD "Connection"): files are written here first and uploaded when
/// the vault is reachable. Survives quitting; retries with backoff; never drops an item on a
/// network error. Notes and audio (milestone 5) go through this.
public actor Outbox {
    public struct Item: Codable, Identifiable, Equatable, Sendable {
        public var id: UUID
        /// Path within the vault.
        public var path: String
        /// New files never overwrite: on a name clash they get "-2", "-3"… (PRD filename rule).
        public var createOnly: Bool
        public var created: Date
        public var attempts: Int
        public var nextAttempt: Date
        public var lastError: String?
    }

    public struct DrainResult: Equatable, Sendable {
        public var uploaded: [String] = []
        /// Set when draining stopped early (offline, signed out, …); remaining items wait.
        public var stoppedBecause: String?
    }

    private let directory: URL
    private var items: [Item]

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = directory.appending(path: "queue.json")
        if let data = try? Data(contentsOf: manifest), let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
        } else {
            items = []
        }
    }

    public var pending: [Item] { items }

    private nonisolated var manifestURL: URL { directory.appending(path: "queue.json") }
    private nonisolated func payloadURL(_ id: UUID) -> URL { directory.appending(path: "\(id.uuidString).data") }

    public func enqueue(path: String, data: Data, createOnly: Bool = true, now: Date = Date()) throws {
        let item = Item(id: UUID(), path: path, createOnly: createOnly, created: now, attempts: 0, nextAttempt: now)
        try data.write(to: payloadURL(item.id), options: .atomic)
        items.append(item)
        persist()
    }

    /// Uploads due items in order. Stops at the first network or auth failure; the rest wait.
    public func drain(to provider: any StorageProvider, vaultPath: String, now: Date = Date()) async -> DrainResult {
        var result = DrainResult()
        for item in items where item.nextAttempt <= now {
            guard let data = try? Data(contentsOf: payloadURL(item.id)) else {
                remove(item.id) // payload gone; nothing to upload
                continue
            }
            do {
                let uploadedPath = try await upload(item, data: data, provider: provider, vaultPath: vaultPath)
                result.uploaded.append(uploadedPath)
                remove(item.id)
            } catch {
                let message = error.localizedDescription
                update(item.id) {
                    $0.attempts += 1
                    // 5 s, 10 s, 20 s … capped at 5 minutes.
                    $0.nextAttempt = now.addingTimeInterval(min(5 * pow(2, Double($0.attempts - 1)), 300))
                    $0.lastError = message
                }
                result.stoppedBecause = message
                break
            }
        }
        return result
    }

    private func upload(_ item: Item, data: Data, provider: any StorageProvider, vaultPath: String) async throws -> String {
        let folder = StoragePath.parent(of: StoragePath.join(vaultPath, item.path))
        if folder != StoragePath.join(vaultPath) { try await provider.createFolder(folder) }
        guard item.createOnly else {
            let path = StoragePath.join(vaultPath, item.path)
            try await provider.write(path, data: data, ifMatch: nil, createOnly: false)
            return path
        }
        for attempt in 1...20 {
            let path = StoragePath.join(vaultPath, attempt == 1 ? item.path : StoragePath.withSuffix(item.path, attempt))
            do {
                try await provider.write(path, data: data, ifMatch: nil, createOnly: true)
                return path
            } catch StorageError.conflict {
                continue
            }
        }
        throw StorageError.conflict(item.path)
    }

    private func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: payloadURL(id))
        persist()
    }

    private func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }
}

extension StoragePath {
    /// "/Notes/2026-10-19 1430 Title.md" → "/Notes/2026-10-19 1430 Title-2.md"
    public static func withSuffix(_ path: String, _ number: Int) -> String {
        let parent = parent(of: path)
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let ext = (name as NSString).pathExtension
        let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        let renamed = ext.isEmpty ? "\(stem)-\(number)" : "\(stem)-\(number).\(ext)"
        return join(parent, renamed)
    }
}
