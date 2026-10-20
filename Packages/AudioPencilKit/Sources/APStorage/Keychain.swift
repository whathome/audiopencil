import Foundation
import Security

/// Nextcloud app passwords in the login Keychain (Internet password items).
public enum Keychain {
    public static func savePassword(_ password: String, for account: NextcloudAccount, service: String = "Nextcloud") throws {
        deletePassword(for: account)
        var query = baseQuery(account)
        query[kSecValueData as String] = Data(password.utf8)
        query[kSecAttrLabel as String] = "Audio Pencil – \(service) (\(account.server.host() ?? ""))"
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StorageError.transport("Couldn't save to the Keychain (\(status)).")
        }
    }

    public static func password(for account: NextcloudAccount) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func deletePassword(for account: NextcloudAccount) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private static func baseQuery(_ account: NextcloudAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: account.server.host() ?? account.server.absoluteString,
            kSecAttrPath as String: account.server.path(),
            kSecAttrAccount as String: account.loginName,
        ]
    }
}
