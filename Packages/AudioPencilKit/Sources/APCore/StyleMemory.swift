import Foundation

/// Remembers which style was used in which app (PRD "per-app defaults").
public struct StyleMemory: Codable, Equatable, Sendable {
    /// App bundle identifier → style id.
    public private(set) var perApp: [String: String] = [:]
    public private(set) var lastUsed: String?

    /// Style for a styled (double-tap) dictation before anything has been used.
    public static let initialStyleID = Style.polished.id

    public init() {}

    /// The style to preselect for `app`: what was last used there, else the last style used anywhere.
    /// Falls back to Polished, then Raw, skipping styles that were deleted or disabled.
    public func defaultStyle(forApp app: String?, among styles: [Style]) -> Style {
        let usable = styles.filter(\.isEnabled)
        for id in [app.flatMap { perApp[$0] }, lastUsed, Self.initialStyleID].compactMap({ $0 }) {
            if let style = usable.first(where: { $0.id == id }) { return style }
        }
        return usable.first(where: \.isRaw) ?? .raw
    }

    public mutating func remember(_ styleID: String, forApp app: String?) {
        lastUsed = styleID
        if let app { perApp[app] = styleID }
    }

    public mutating func forget(app: String) {
        perApp[app] = nil
    }
}
