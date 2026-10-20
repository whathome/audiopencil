import Foundation

/// A folder on this Mac, e.g. an Obsidian vault in iCloud Drive
/// (~/Library/Mobile Documents/iCloud~md~obsidian/Documents/<Vault>). iCloud does the syncing.
/// Paths are relative to `root`.
public struct LocalFolderStorage: StorageProvider {
    public let root: URL
    /// Deletions go to the macOS Trash (recoverable), like Nextcloud's trash bin for WebDAV.
    public var usesTrash: Bool

    public init(root: URL, usesTrash: Bool = true) {
        self.root = root
        self.usesTrash = usesTrash
    }

    #if os(macOS)
    /// Obsidian's iCloud container, if Obsidian has created one on this Mac.
    public static var obsidianICloudFolder: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/iCloud~md~obsidian/Documents", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    #endif

    private static let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]

    func url(for path: String) -> URL {
        path.split(separator: "/").reduce(root) { $0.appending(path: String($1)) }
    }

    public func list(_ path: String) async throws -> [StorageItem] {
        let folder = url(for: path)
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Self.keys)
        } catch {
            throw FileManager.default.fileExists(atPath: folder.path) ? StorageError.transport(error.localizedDescription) : StorageError.notFound(path)
        }
        return urls.compactMap { item(for: $0, path: StoragePath.join(path, $0.lastPathComponent)) }
            .sorted { $0.path < $1.path }
    }

    public func item(at path: String) async throws -> StorageItem? {
        let fileURL = url(for: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return item(for: fileURL, path: StoragePath.join(path))
    }

    public func read(_ path: String) async throws -> (data: Data, etag: String?) {
        let fileURL = url(for: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw StorageError.notFound(path) }
        do {
            let data = try Data(contentsOf: fileURL)
            return (data, item(for: fileURL, path: path)?.etag)
        } catch {
            throw StorageError.transport(error.localizedDescription)
        }
    }

    @discardableResult
    public func write(_ path: String, data: Data, ifMatch: String?, createOnly: Bool) async throws -> String? {
        let fileURL = url(for: path)
        let existing = try await item(at: path)
        if createOnly, existing != nil { throw StorageError.conflict(path) }
        if let ifMatch, existing?.etag != ifMatch { throw StorageError.conflict(path) }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw StorageError.transport(error.localizedDescription)
        }
        return try await item(at: path)?.etag
    }

    public func createFolder(_ path: String) async throws {
        do {
            try FileManager.default.createDirectory(at: url(for: path), withIntermediateDirectories: true)
        } catch {
            throw StorageError.transport(error.localizedDescription)
        }
    }

    public func delete(_ path: String) async throws {
        let fileURL = url(for: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            if usesTrash {
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
            } else {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            throw StorageError.transport(error.localizedDescription)
        }
    }

    private func item(for url: URL, path: String) -> StorageItem? {
        guard let values = try? url.resourceValues(forKeys: Set(Self.keys)) else { return nil }
        let modified = values.contentModificationDate
        let size = values.fileSize
        // Local files have no ETag; modification time plus size changes on every write.
        let etag = modified.map { "\"\(Int64($0.timeIntervalSince1970 * 1_000_000))-\(size ?? 0)\"" }
        return StorageItem(path: path, isFolder: values.isDirectory ?? false, etag: etag, size: size, modified: modified)
    }
}
