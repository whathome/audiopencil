import APCore
import AppKit
import Carbon.HIToolbox
import SwiftUI

extension KeyShortcut {
    /// "⌃⌥Space", "⌘⇧D", "F5": modifiers, then the key as the current keyboard layout labels it.
    var displayText: String { modifierSymbols + Self.keyName(keyCode) }

    static func keyName(_ keyCode: Int) -> String {
        let named: [Int: String] = [
            kVK_Space: String(localized: "Space"), kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
            kVK_F18: "F18", kVK_F19: "F19",
        ]
        if let name = named[keyCode] { return name }
        return character(forKeyCode: keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    /// The character the key types in the current layout, without modifiers.
    private static func character(forKeyCode keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }

    /// Function keys work alone; anything else needs ⌘, ⌃ or ⌥ so it can't fire while typing.
    var isUsable: Bool {
        let functionKeys: Set<Int> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                      kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19]
        return functionKeys.contains(keyCode) || modifiers & (Self.command | Self.control | Self.option) != 0
    }
}

/// Click, then press a key combination. Escape cancels. The global hotkeys stand aside meanwhile.
struct ShortcutRecorder: View {
    @Bindable var app: AppModel
    @State private var recording = false
    @State private var monitor: Any?
    @State private var problem: LocalizedStringResource?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Press keys…" : "\(app.settings.fallbackShortcut.displayText)" as LocalizedStringResource)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .frame(minWidth: 90)
            }
            .help(Text("Click, then press the keys to use. Escape cancels."))
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        problem = nil
        recording = true
        app.pauseHotkeys(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            var modifiers: UInt64 = 0
            if event.modifierFlags.contains(.command) { modifiers |= KeyShortcut.command }
            if event.modifierFlags.contains(.control) { modifiers |= KeyShortcut.control }
            if event.modifierFlags.contains(.option) { modifiers |= KeyShortcut.option }
            if event.modifierFlags.contains(.shift) { modifiers |= KeyShortcut.shift }
            let shortcut = KeyShortcut(keyCode: Int(event.keyCode), modifiers: modifiers)
            if shortcut.isUsable {
                app.settings.fallbackShortcut = shortcut
                stop()
            } else {
                problem = "Add ⌘, ⌃ or ⌥ (or use a function key)"
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        app.pauseHotkeys(false)
    }
}
