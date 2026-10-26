import AppKit
import Testing

@MainActor struct SidebarWindowLayoutTests {
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    private func window(width: CGFloat, x: CGFloat = 100) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: x, y: 100, width: width, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.maxSize = NSSize(width: width, height: 1000)
        return window
    }

    @Test func reopeningRestoresTheSidebarSpaceDespiteTheOldWidthLimit() {
        let window = window(width: 753)
        defer { window.close() }
        SidebarWindowLayout.expand(window, maximumContentWidth: 909, visibleFrame: screen)
        #expect(window.contentRect(forFrameRect: window.frame).width == 909)
        #expect(window.maxSize.width == 909)
    }

    @Test func automaticallyCollapsedWindowsGrowPastTheRailThreshold() {
        let window = window(width: 520)
        defer { window.close() }
        SidebarWindowLayout.expand(window, maximumContentWidth: 909, visibleFrame: screen)
        #expect(window.contentRect(forFrameRect: window.frame).width >= SidebarWindowLayout.railBelowWidth)
    }

    @Test func expansionPreservesHeightAndFitsTheCurrentScreen() {
        let window = window(width: 753, x: 680)
        defer { window.close() }
        let originalHeight = window.frame.height
        SidebarWindowLayout.expand(window, maximumContentWidth: 909, visibleFrame: screen)
        #expect(window.frame.height == originalHeight)
        #expect(window.frame.minX >= screen.minX)
        #expect(window.frame.maxX <= screen.maxX)
    }

    @Test func repeatedCollapseAndExpandRestoresTheSameWidth() {
        let window = window(width: 753)
        defer { window.close() }
        for _ in 0..<3 {
            window.maxSize.width = 753
            var frame = window.frame
            frame.size.width = 753
            window.setFrame(frame, display: false)
            SidebarWindowLayout.expand(window, maximumContentWidth: 909, visibleFrame: screen)
            #expect(window.contentRect(forFrameRect: window.frame).width == 909)
        }
    }
}
