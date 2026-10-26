import AppKit

enum SidebarWindowLayout {
    static let railBelowWidth: CGFloat = 760
    static let sidebarWidth: CGFloat = 220
    static let railWidth: CGFloat = 64

    static func expand(_ window: NSWindow, maximumContentWidth: CGFloat, visibleFrame: NSRect? = nil) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        var content = window.contentRect(forFrameRect: window.frame)
        content.size.width = min(maximumContentWidth, max(railBelowWidth, content.width + sidebarWidth - railWidth))
        var frame = window.frameRect(forContentRect: content)
        if let available = visibleFrame ?? window.screen?.visibleFrame {
            frame.size.width = min(frame.width, available.width)
            frame.origin.x = max(available.minX, min(frame.minX, available.maxX - frame.width))
        }
        // SwiftUI publishes the expanded width limit after the toggle; don't let the old rail limit clamp it.
        var maximum = window.maxSize
        maximum.width = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: maximumContentWidth, height: 0)).width
        window.maxSize = maximum
        window.setFrame(frame, display: true)
    }
}
