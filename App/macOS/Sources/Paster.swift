import AppKit
import ApplicationServices

/// Puts text on the clipboard and pastes it into the focused field with a synthetic ⌘V.
enum Paster {
    enum Outcome: String {
        case pasted
        case clipboardOnly
    }

    /// Roles that definitely can't take pasted text. Anything else (including unknown roles and
    /// apps that don't expose their focus, like many Electron apps) gets the paste.
    private static let nonTextRoles: Set<String> = [
        "AXList", "AXOutline", "AXTable", "AXBrowser", "AXButton", "AXImage", "AXWindow",
        "AXApplication", "AXMenuBar", "AXMenu", "AXMenuItem", "AXCheckBox", "AXRadioButton",
        "AXSlider", "AXScrollBar", "AXToolbar", "AXPopUpButton", "AXDockItem",
    ]

    static func deliver(_ text: String) -> Outcome {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard AXIsProcessTrusted(), focusMightAcceptText() else { return .clipboardOnly }
        postCommandV()
        return .pasted
    }

    private static func focusMightAcceptText() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, "AXFocusedUIElement" as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else {
            return true // can't tell; paste anyway
        }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(focused as! AXUIElement, "AXRole" as CFString, &role)
        return !nonTextRoles.contains(role as? String ?? "")
    }

    private static func postCommandV() {
        // Key code 9 is V on ANSI-style layouts (US, Canadian English). Layout-aware lookup can come later.
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: isDown) else { continue }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: HotkeyMonitor.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}
