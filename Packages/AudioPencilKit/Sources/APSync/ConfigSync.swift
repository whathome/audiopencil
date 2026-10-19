import APCore
import APStorage
import Foundation

/// Keeps the vault's settings file and the app's settings in step.
///
/// Each sync: check the file's ETag; if it or the local settings changed since the last agreed
/// version (the base), read it, three-way merge, and write back conditionally (If-Match). A 412
/// means someone wrote in between: re-read and merge again. A YAML error in the file stops syncing
/// without touching the file.
public actor ConfigSync {
    public struct State: Codable, Equatable, Sendable {
        public var base: SharedConfig?
        public var etag: String?
        public var location: String?
    }

    public enum Outcome: Equatable, Sendable {
        /// Nothing changed anywhere.
        case unchanged(SharedConfig)
        /// Merged result; apply it to the app.
        case merged(SharedConfig, wroteFile: Bool)
    }

    private let stateURL: URL
    private var state: State

    public init(stateURL: URL) {
        self.stateURL = stateURL
        if let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = State()
        }
    }

    public static func filePath(inVault vault: String) -> String {
        StoragePath.join(vault, ConfigDocument.folderName, ConfigDocument.fileName)
    }

    /// `location` identifies the vault (provider + path); switching vaults starts a fresh base.
    public func sync(local: SharedConfig, device: String, provider: any StorageProvider, vaultPath: String, location: String) async throws -> Outcome {
        if state.location != location {
            state = State(base: nil, etag: nil, location: location)
        }
        let path = Self.filePath(inVault: vaultPath)

        for _ in 0..<3 {
            guard let item = try await provider.item(at: path) else {
                // First device: create the folder and the file from local settings.
                try await provider.createFolder(StoragePath.join(vaultPath, ConfigDocument.folderName))
                do {
                    let etag = try await writeFile(local, path: path, ifMatch: nil, createOnly: true, provider: provider)
                    save(State(base: local, etag: etag, location: location))
                    return .merged(local, wroteFile: true)
                } catch StorageError.conflict {
                    continue // another device created it just now
                }
            }

            if item.etag != nil, item.etag == state.etag, let base = state.base, base == local {
                return .unchanged(base)
            }

            let remote: SharedConfig
            let remoteEtag: String?
            if item.etag != nil, item.etag == state.etag, let base = state.base {
                (remote, remoteEtag) = (base, item.etag) // file untouched; only local changed
            } else {
                let (data, etag) = try await provider.read(path)
                remote = try ConfigDocument.parse(String(decoding: data, as: UTF8.self))
                remoteEtag = etag ?? item.etag
            }

            let merged = ConfigMerger.merge(base: state.base, local: local, remote: remote, device: device)
            if merged == remote {
                save(State(base: merged, etag: remoteEtag, location: location))
                return .merged(merged, wroteFile: false)
            }
            do {
                let etag = try await writeFile(merged, path: path, ifMatch: remoteEtag, createOnly: false, provider: provider)
                save(State(base: merged, etag: etag, location: location))
                return .merged(merged, wroteFile: true)
            } catch StorageError.conflict {
                continue // changed under us: re-read and merge again
            }
        }
        throw StorageError.conflict(path)
    }

    /// The last version both sides agreed on (to build the local side from, so fields the app
    /// doesn't edit, like tags and other devices, aren't mistaken for deletions).
    public var base: SharedConfig? { state.base }

    /// Forget the base (e.g. after signing out), so the next sync treats the file as new.
    public func reset() {
        save(State())
    }

    private func writeFile(_ config: SharedConfig, path: String, ifMatch: String?, createOnly: Bool, provider: any StorageProvider) async throws -> String? {
        let data = Data(ConfigDocument.render(config).utf8)
        if let etag = try await provider.write(path, data: data, ifMatch: ifMatch, createOnly: createOnly) {
            return etag
        }
        return try await provider.item(at: path)?.etag
    }

    private func save(_ newState: State) {
        state = newState
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(newState) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }
}
