import AppKit
import ApplicationServices
import Carbon.HIToolbox

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
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = keyCode(producing: "v") ?? 9 // 9 is V on ANSI layouts (US, UK, AZERTY, QWERTZ)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: isDown) else { continue }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: HotkeyMonitor.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    /// The key that types `character` with ⌘ held in the current keyboard layout. Dvorak puts V elsewhere;
    /// "Dvorak – QWERTY ⌘" switches back to QWERTY while ⌘ is down, which translating with ⌘ covers.
    private static func keyCode(producing character: Character) -> CGKeyCode? {
        guard let layoutSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(layoutSource, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> CGKeyCode? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            let commandState = UInt32((cmdKey >> 8) & 0xFF)
            for code in 0..<CGKeyCode(128) {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDisplay), commandState, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
                )
                if status == noErr, length == 1, String(utf16CodeUnits: chars, count: 1).lowercased() == String(character) {
                    return code
                }
            }
            return nil
        }
    }
}
