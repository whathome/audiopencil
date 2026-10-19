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
        case fnDown
        case fnUp
        case escape
        case returnKey
        case fallbackShortcut
        /// Any other key or modifier. Never swallowed; only spoils Fn taps.
        case other
    }

    /// Marks events we synthesise (the ⌘V paste) so the tap ignores them.
    static let syntheticMarker: Int64 = 0x4150_4E43

    /// Return true to swallow the event. Timestamps are seconds of system uptime.
    var handler: ((KeyEvent, TimeInterval) -> Bool)?
    /// Last modifier event, for diagnosing Fn detection. Never contains typed characters.
    var onDiagnostic: ((String) -> Void)?

    private(set) var isActive = false
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnIsDown = false
    private var swallowedKeyUps: Set<Int64> = []

    private enum KeyCode {
        static let function: Int64 = 63      // kVK_Function
        static let escape: Int64 = 53
        static let returnKey: Int64 = 36
        static let keypadEnter: Int64 = 76
        static let space: Int64 = 49
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

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // Not event.timestamp: on Apple silicon that's in Mach ticks, not nanoseconds.
        // The callback runs promptly on the main run loop, so uptime-now is accurate enough for taps.
        let time = ProcessInfo.processInfo.systemUptime

        switch type {
        case .flagsChanged:
            if keyCode == KeyCode.function {
                let down = event.flags.contains(.maskSecondaryFn)
                onDiagnostic?("Fn \(down ? "down" : "up") (key code \(keyCode))")
                guard down != fnIsDown else { return false }
                fnIsDown = down
                _ = handler?(down ? .fnDown : .fnUp, time)
            } else {
                onDiagnostic?("Modifier key code \(keyCode)")
                _ = handler?(.other, time)
            }
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
            } else if keyCode == KeyCode.space, flags.contains([.maskControl, .maskAlternate]), !flags.contains(.maskCommand) {
                keyEvent = .fallbackShortcut
            } else {
                keyEvent = .other
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
