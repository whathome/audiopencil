import APCore
import Foundation

/// Where this device's vault lives. One location at a time for the MVP: Nextcloud or a local folder
/// (typically an Obsidian vault in iCloud Drive).
public struct VaultSettings: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case nextcloud
        case localFolder
        /// Any WebDAV server (Synology, ownCloud, a hosting provider…): URL, user name, password.
        case webdav
    }

    public var kind: Kind = .nextcloud
    /// Signed-in Nextcloud account (password in the Keychain).
    public var account: NextcloudAccount?
    /// Vault folder inside the Nextcloud files, e.g. "/Obsidian/Vault".
    public var remoteVaultPath: String?
    /// Bookmark to the local vault folder, so it survives renames and moves.
    public var localBookmark: Data?
    /// Last known path of the local vault, for display.
    public var localPath: String?
    /// A generic WebDAV server: `server` is the WebDAV root URL (password in the Keychain).
    public var webdav: NextcloudAccount?
    /// Folder on the WebDAV server, e.g. "/Notes".
    public var webdavPath: String?
    /// How notes are written here, from whether the folder is an Obsidian vault. Nil until first checked.
    public var layout: NoteLayout?

    public init() {}

    public var isConfigured: Bool {
        switch kind {
        case .nextcloud: account != nil && remoteVaultPath != nil
        case .localFolder: localBookmark != nil
        case .webdav: webdav != nil && webdavPath != nil
        }
    }
}
