import Foundation

/// Where this device's vault lives. One location at a time for the MVP: Nextcloud or a local folder
/// (typically an Obsidian vault in iCloud Drive).
public struct VaultSettings: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case nextcloud
        case localFolder
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

    public init() {}

    public var isConfigured: Bool {
        switch kind {
        case .nextcloud: account != nil && remoteVaultPath != nil
        case .localFolder: localBookmark != nil
        }
    }
}
