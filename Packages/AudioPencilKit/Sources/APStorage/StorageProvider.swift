import Foundation

/// A file or folder in the vault. `path` is absolute within the provider, "/"-separated, no trailing slash
/// (the provider root is "/").
public struct StorageItem: Identifiable, Hashable, Sendable {
    public var path: String
    public var isFolder: Bool
    /// Version tag: changes whenever the content changes. Used for conflict-safe writes.
    public var etag: String?
    public var size: Int?
    public var modified: Date?

    public var id: String { path }
    public var name: String { path.split(separator: "/").last.map(String.init) ?? "/" }
    public var isHidden: Bool { name.hasPrefix(".") }

    public init(path: String, isFolder: Bool, etag: String? = nil, size: Int? = nil, modified: Date? = nil) {
        self.path = path
        self.isFolder = isFolder
        self.etag = etag
        self.size = size
        self.modified = modified
    }
}

public enum StorageError: LocalizedError, Equatable {
    case notFound(String)
    /// The file changed since it was read (ETag mismatch). Re-read, merge, try again.
    case conflict(String)
    case unauthorized
    case storageFull
    case invalidServer(String)
    case server(status: Int)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let path): String(localized: "\(path) doesn't exist.", bundle: .module)
        case .conflict(let path): String(localized: "\(path) was changed somewhere else.", bundle: .module)
        case .unauthorized: String(localized: "The server rejected the sign-in. Sign in again.", bundle: .module)
        case .storageFull: String(localized: "The storage is full.", bundle: .module)
        case .invalidServer(let detail): detail
        case .server(let status): String(localized: "The server returned an error (HTTP \(status)).", bundle: .module)
        case .transport(let detail): detail
        }
    }
}

/// Where the vault lives. Nextcloud (WebDAV) or a folder on this Mac (e.g. an Obsidian vault in iCloud Drive).
/// Paths are relative to the provider's root; the vault folder is chosen separately.
public protocol StorageProvider: Sendable {
    /// Immediate children of a folder.
    func list(_ path: String) async throws -> [StorageItem]
    func item(at path: String) async throws -> StorageItem?
    func read(_ path: String) async throws -> (data: Data, etag: String?)
    /// Writes a file. `ifMatch`: only if the current version has this ETag. `createOnly`: fail if it exists.
    /// Throws `.conflict` when the condition fails. Returns the new ETag when known.
    @discardableResult
    func write(_ path: String, data: Data, ifMatch: String?, createOnly: Bool) async throws -> String?
    func createFolder(_ path: String) async throws
    func delete(_ path: String) async throws
}

public enum StoragePath {
    /// Joins path components into a normalised absolute path.
    public static func join(_ parts: String...) -> String {
        let components = parts.flatMap { $0.split(separator: "/") }.map(String.init)
        return "/" + components.joined(separator: "/")
    }

    public static func parent(of path: String) -> String {
        var components = path.split(separator: "/")
        guard !components.isEmpty else { return "/" }
        components.removeLast()
        return "/" + components.joined(separator: "/")
    }
}
