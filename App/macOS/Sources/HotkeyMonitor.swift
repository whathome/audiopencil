import AppKit
import APCore
import CoreGraphics

/// Global keyboard watcher built on a session event tap.
///
/// Reports Fn presses and the few keys dictation cares about, and lets the handler swallow
/// Escape / Return / the fallback shortcut while recording so they don't reach the frontmost app.
/// An active tap needs Accessibility permission. It sees no keystrokes while Secure Input is on
/// (password fields, Terminal's Secure Keyboard Entry).
final class HotkeyMonitor {
    enum KeyEvent: Equatable {
        /// The gesture key (Fn, Right ⌥ or Right ⌘) went down or up.
        case fnDown
        case fnUp
        case escape
        case returnKey
        case fallbackShortcut
        /// A number key 0–9 with no modifiers (top row or keypad): picks a style while recording.
        case digit(Int)
        /// Any other key or modifier. Never swallowed; only spoils Fn taps.
        case other
    }

    /// Marks events we synthesise (the ⌘V paste) so the tap ignores them.
    static let syntheticMarker: Int64 = 0x4150_4E43

    /// Return true to swallow the event. Timestamps are seconds of system uptime.
    var handler: ((KeyEvent, TimeInterval) -> Bool)?
    /// Fn-related events, for diagnosing tap detection. Never contains typed characters;
    /// key codes of ordinary keys are only reported within a second of an Fn press.
    var onDiagnostic: ((String) -> Void)?

    private(set) var isActive = false
    /// Which key the tap gestures use.
    var gestureKey: GestureKey = .fn
    /// The shortcut that toggles dictation.
    var shortcut: KeyShortcut = .controlOptionSpace
    /// Settings is recording a new shortcut: report nothing, swallow nothing.
    var isPaused = false
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnIsDown = false
    private var lastFnChange: TimeInterval = 0
    private var swallowedKeyUps: Set<Int64> = []

    private enum KeyCode {
        static let function: Int64 = 63      // kVK_Function
        static let escape: Int64 = 53
        static let returnKey: Int64 = 36
        static let keypadEnter: Int64 = 76
        static let space: Int64 = 49
        /// Top-row and keypad number keys → digit (key codes are layout-independent positions).
        static let digits: [Int64: Int] = [
            29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
            82: 0, 83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9,
        ]
        /// Key events some keyboards emit for the Fn/Globe key itself.
        static let globeArtifacts: Set<Int64> = [63, 179]
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.hotkey.error("Couldn't create event tap (Accessibility not granted?)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        isActive = true
        Log.hotkey.notice("Event tap active")
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        isActive = false
    }

    /// Returns true to swallow the event.
    fileprivate func process(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Log.hotkey.notice("Event tap was disabled (\(type.rawValue)); re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        default:
            break
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker || isPaused { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // Not event.timestamp: on Apple silicon that's in Mach ticks, not nanoseconds.
        // The callback runs promptly on the main run loop, so uptime-now is accurate enough for taps.
        let time = ProcessInfo.processInfo.systemUptime

        switch type {
        case .flagsChanged:
            // The key's state comes from the flags, whatever key code the event carries (the Globe key
            // doesn't always report kVK_Function). Right ⌥ and ⌘ have their own device-dependent bits.
            let down = isGestureKeyDown(event.flags)
            if down != fnIsDown {
                fnIsDown = down
                lastFnChange = time
                onDiagnostic?("Fn \(down ? "down" : "up") (flags, key code \(keyCode))")
                _ = handler?(down ? .fnDown : .fnUp, time)
            } else {
                if fnIsDown || time - lastFnChange < 1 {
                    onDiagnostic?("Other modifier near Fn (key code \(keyCode)) spoils the tap")
                }
                _ = handler?(.other, time)
            }
            return false

        case .keyDown where KeyCode.globeArtifacts.contains(keyCode),
             .keyUp where KeyCode.globeArtifacts.contains(keyCode):
            // The built-in keyboard sends key code 179 down/up right after each Fn release.
            // Treating it as "other input" broke every double-tap.
            onDiagnostic?("Globe key \(type == .keyDown ? "down" : "up") event (key code \(keyCode)), ignored")
            return false

        case .keyDown:
            let flags = event.flags
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if isRepeat { return swallowedKeyUps.contains(keyCode) }

            let keyEvent: KeyEvent
            let commandLike: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            if keyCode == KeyCode.escape {
                keyEvent = .escape
            } else if keyCode == KeyCode.returnKey || keyCode == KeyCode.keypadEnter, flags.intersection(commandLike).isEmpty {
                keyEvent = .returnKey
            } else if Int(keyCode) == shortcut.keyCode, flags.rawValue & KeyShortcut.allModifiers == shortcut.modifiers {
                keyEvent = .fallbackShortcut
            } else if let digit = KeyCode.digits[keyCode], flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
                keyEvent = .digit(digit)
            } else {
                keyEvent = .other
                // Key codes only near an Fn press, to diagnose taps without logging typing.
                if fnIsDown || time - lastFnChange < 1 {
                    onDiagnostic?("Key down near Fn (key code \(keyCode)) spoils the tap")
                }
            }
            let swallow = handler?(keyEvent, time) ?? false
            if swallow { swallowedKeyUps.insert(keyCode) }
            return swallow

        case .keyUp:
            return swallowedKeyUps.remove(keyCode) != nil

        default:
            return false
        }
    }

    private func isGestureKeyDown(_ flags: CGEventFlags) -> Bool {
        switch gestureKey {
        case .fn: flags.contains(.maskSecondaryFn)
        case .rightOption: flags.rawValue & 0x40 != 0 // NX_DEVICERALTKEYMASK
        case .rightCommand: flags.rawValue & 0x10 != 0 // NX_DEVICERCMDKEYMASK
        }
    }
}

private nonisolated func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    // The tap's run-loop source is on the main run loop, so this runs on the main thread
    // and nothing actually crosses threads.
    nonisolated(unsafe) let monitorPointer = refcon
    nonisolated(unsafe) let tappedEvent = event
    let swallow = MainActor.assumeIsolated {
        Unmanaged<HotkeyMonitor>.fromOpaque(monitorPointer).takeUnretainedValue().process(type: type, event: tappedEvent)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
