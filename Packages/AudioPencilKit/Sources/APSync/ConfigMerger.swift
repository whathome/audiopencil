import Foundation

/// Three-way merge of the settings file: `base` is the version both sides last agreed on,
/// `local` has the app's changes since, `remote` has edits from Obsidian or another device.
/// Rules: a side that didn't change defers to the side that did; if both changed the same thing,
/// the vault wins (it's the source of truth), except this device's own section, where local wins.
/// With no base (first sync on an existing file) lists and styles are unioned.
public enum ConfigMerger {
    public static func merge(base: SharedConfig?, local: SharedConfig, remote: SharedConfig, device: String) -> SharedConfig {
        var merged = remote
        merged.version = max(local.version, remote.version)
        merged.vocabulary = mergeList(base: base?.vocabulary, local: local.vocabulary, remote: remote.vocabulary)
        let languages = Set(local.languageVocabulary.keys).union(remote.languageVocabulary.keys).union(base.map { Array($0.languageVocabulary.keys) } ?? [])
        merged.languageVocabulary = Dictionary(uniqueKeysWithValues: languages.map { code in
            (code, mergeList(base: base.map { $0.languageVocabulary[code] ?? [] }, local: local.languageVocabulary[code] ?? [], remote: remote.languageVocabulary[code] ?? []))
        }).filter { !$0.value.isEmpty }
        merged.tags = mergeList(base: base?.tags, local: local.tags, remote: remote.tags)
        merged.styles = mergeStyles(base: base?.styles, local: local.styles, remote: remote.styles)
        if let base, local.expireRegularAudio != base.expireRegularAudio, remote.expireRegularAudio == base.expireRegularAudio {
            merged.expireRegularAudio = local.expireRegularAudio // changed here only
        }
        merged.writingSamples = mergeByID(base: base?.writingSamples, local: local.writingSamples, remote: remote.writingSamples)

        let localDevice = local.devices[device]
        let baseDevice = base?.devices[device]
        let remoteDevice = remote.devices[device]
        if let localDevice {
            if let remoteDevice, base != nil, localDevice == baseDevice {
                merged.devices[device] = remoteDevice // edited in Obsidian, unchanged here
            } else {
                merged.devices[device] = localDevice
            }
        }
        return merged
    }

    static func mergeList(base: [String]?, local: [String], remote: [String]) -> [String] {
        guard let base else {
            return remote + local.filter { !remote.contains($0) }
        }
        let added = local.filter { !base.contains($0) }
        let removed = Set(base.filter { !local.contains($0) })
        var result = remote.filter { !removed.contains($0) }
        for item in added where !result.contains(item) { result.append(item) }
        return result
    }

    static func mergeStyles(base: [ConfigStyle]?, local: [ConfigStyle], remote: [ConfigStyle]) -> [ConfigStyle] {
        mergeByID(base: base, local: local, remote: remote)
    }

    /// Three-way merge of a list of items keyed by id (styles, writing samples).
    static func mergeByID<Item: Equatable & Identifiable>(base: [Item]?, local: [Item], remote: [Item]) -> [Item] where Item.ID == String {
        func find(_ id: String, in list: [Item]?) -> Item? { list?.first { $0.id == id } }
        var result: [Item] = []

        for remoteStyle in remote {
            let localStyle = find(remoteStyle.id, in: local)
            let baseStyle = find(remoteStyle.id, in: base)
            switch (localStyle, baseStyle) {
            case (nil, nil):
                result.append(remoteStyle) // added elsewhere
            case (nil, .some(let baseStyle)):
                // Deleted here: honour it unless it was edited elsewhere meanwhile.
                if remoteStyle != baseStyle { result.append(remoteStyle) }
            case (.some(let localStyle), let baseStyle):
                if let baseStyle, remoteStyle == baseStyle {
                    result.append(localStyle) // only changed here
                } else {
                    result.append(remoteStyle) // changed elsewhere (or both): vault wins
                }
            }
        }
        for localStyle in local where find(localStyle.id, in: remote) == nil {
            if let baseStyle = find(localStyle.id, in: base) {
                // Deleted elsewhere: honour it unless it was edited here meanwhile.
                if localStyle != baseStyle { result.append(localStyle) }
            } else {
                result.append(localStyle) // added here
            }
        }
        return result
    }
}
