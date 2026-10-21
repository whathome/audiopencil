import Foundation

#if os(macOS)

/// An Obsidian vault already on this Mac, offered in setup.
public struct FoundVault: Identifiable, Hashable, Sendable {
    public let url: URL
    /// When Obsidian last opened it, if Obsidian knows it.
    public let lastOpened: Date?

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
}

/// Finds Obsidian vaults on this Mac from Obsidian's own list of the vaults it has opened (obsidian.json).
///
/// Folders in iCloud Drive or another cloud provider (~/Library/Mobile Documents, ~/Library/CloudStorage)
/// are taken on Obsidian's word, not checked: touching them makes macOS ask for access to the provider's
/// files, and that should only happen once someone picks one. Elsewhere, only folders that still exist and
/// hold a `.obsidian` folder count. Reads the disk, so call it off the main thread.
public enum ObsidianVaults {
    /// Obsidian's list of the vaults it has opened.
    public static var obsidianConfig: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/obsidian/obsidian.json", directoryHint: .notDirectory)
    }

    /// Most recently opened first.
    public static func find(config: URL = obsidianConfig, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [FoundVault] {
        guard let data = try? Data(contentsOf: config),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vaults = json["vaults"] as? [String: [String: Any]]
        else { return [] }
        var found: [String: FoundVault] = [:]
        for entry in vaults.values {
            guard let path = entry["path"] as? String else { continue }
            let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            guard isCloudManaged(url, home: home) || isVault(url) else { continue }
            let opened = (entry["ts"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            found[url.path] = FoundVault(url: url, lastOpened: opened)
        }
        return found.values.sorted { ($0.lastOpened ?? .distantPast) > ($1.lastOpened ?? .distantPast) }
    }

    /// The registered vault a folder belongs to: the vault itself, or the deepest vault containing it. A
    /// folder chosen inside a vault ("Work" in iCloud's "Documents" vault) is part of that vault, and
    /// Obsidian's links name the vault and give paths from its root.
    public static func vault(containing folder: URL, among vaults: [FoundVault]) -> (vault: FoundVault, pathInVault: String)? {
        let folderParts = folder.standardizedFileURL.pathComponents
        let match = vaults
            .filter { vault in
                let parts = vault.url.standardizedFileURL.pathComponents
                return parts.count <= folderParts.count && Array(folderParts.prefix(parts.count)) == parts
            }
            .max { $0.url.pathComponents.count < $1.url.pathComponents.count }
        guard let match else { return nil }
        let rest = folderParts.dropFirst(match.url.standardizedFileURL.pathComponents.count)
        return (match, rest.joined(separator: "/"))
    }

    /// Inside iCloud Drive or a File Provider folder (Dropbox, OneDrive, Google Drive…).
    public static func isCloudManaged(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let path = url.standardizedFileURL.path
        return ["Library/Mobile Documents", "Library/CloudStorage"].contains { path.hasPrefix(home.appending(path: $0).path + "/") }
    }

    private static func isVault(_ url: URL) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.appending(path: ".obsidian").path, isDirectory: &isFolder) && isFolder.boolValue
    }
}
#endif

/// Obsidian's URL scheme.
public enum ObsidianLinks {
    /// `obsidian://open` for a file at `path` (from the vault root, with or without a leading slash).
    public static func openURL(vault name: String, file path: String) -> URL? {
        var components = URLComponents(string: "obsidian://open")
        let file = path.split(separator: "/").joined(separator: "/")
        components?.queryItems = [URLQueryItem(name: "vault", value: name), URLQueryItem(name: "file", value: file)]
        return components?.url
    }
}
