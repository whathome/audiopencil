import APCore
import CoreGraphics
import Foundation

/// The synchronous input path: value-only decisions, without UI, audio, logging or model work.
nonisolated struct HotkeyEventProcessor {
    enum KeyEvent: Equatable, Sendable {
        case fnDown, fnUp, escape, returnKey, fallbackShortcut
        case digit(Int)
        case other
    }

    struct Policy: Sendable {
        var isEnabled = true
        var swallowEscape = false
        var swallowReturn = false
        var swallowDigits = false
        var swallowShortcut = false
    }

    struct Decision: Sendable {
        var event: KeyEvent?
        var swallow = false
        var diagnostic: String?
        var tapTimedOut = false
    }

    static let syntheticMarker: Int64 = 0x4150_4E43
    var gestureKey: GestureKey = .fn
    var shortcut: KeyShortcut = .controlOptionSpace
    var isPaused = false
    var policy = Policy()
    private(set) var hasTimedOut = false
    private var fnIsDown = false
    private var lastFnChange: TimeInterval?
    private var reportedOtherInput = false
    private var swallowedKeyUps: Set<Int64> = []

    private static let digits: [Int64: Int] = [
        29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
        82: 0, 83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9,
    ]

    mutating func process(
        type: CGEventType, keyCode: Int64, flags: CGEventFlags = [],
        isRepeat: Bool = false, isSynthetic: Bool = false, at time: TimeInterval
    ) -> Decision {
        if type == .tapDisabledByTimeout {
            guard !hasTimedOut else { return Decision() }
            hasTimedOut = true
            swallowedKeyUps.removeAll()
            return Decision(tapTimedOut: true)
        }
        guard !hasTimedOut else { return Decision() }
        guard !isSynthetic else { return Decision() }
        // A swallowed down must have its matching up swallowed even if recording stops in between.
        if type == .keyUp { return Decision(swallow: swallowedKeyUps.remove(keyCode) != nil) }
        if type == .keyDown, isRepeat { return Decision(swallow: swallowedKeyUps.contains(keyCode)) }
        guard !isPaused, policy.isEnabled else {
            fnIsDown = false
            lastFnChange = nil
            return Decision()
        }

        if type == .flagsChanged {
            let down: Bool
            switch gestureKey {
            case .fn: down = flags.contains(.maskSecondaryFn)
            case .rightOption: down = flags.rawValue & 0x40 != 0
            case .rightCommand: down = flags.rawValue & 0x10 != 0
            }
            if down != fnIsDown {
                fnIsDown = down
                lastFnChange = time
                reportedOtherInput = false
                return Decision(event: down ? .fnDown : .fnUp,
                                diagnostic: "Fn \(down ? "down" : "up") (flags, key code \(keyCode))")
            }
            return otherInput(at: time, diagnostic: "Other modifier near Fn (key code \(keyCode)) spoils the tap")
        }

        guard type == .keyDown else { return Decision() }
        if keyCode == 63 || keyCode == 179 { return Decision() } // Fn/Globe's own key events.
        let commandLike: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        let event: KeyEvent
        let swallow: Bool
        if keyCode == 53 {
            event = .escape
            swallow = policy.swallowEscape
        } else if (keyCode == 36 || keyCode == 76), flags.intersection(commandLike).isEmpty {
            event = .returnKey
            swallow = policy.swallowReturn
        } else if Int(keyCode) == shortcut.keyCode, flags.rawValue & KeyShortcut.allModifiers == shortcut.modifiers {
            event = .fallbackShortcut
            swallow = policy.swallowShortcut
        } else if let digit = Self.digits[keyCode], flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            event = .digit(digit)
            swallow = policy.swallowDigits
        } else {
            return otherInput(at: time, diagnostic: "Key down near Fn (key code \(keyCode)) spoils the tap")
        }
        guard swallow else { return Decision() }
        swallowedKeyUps.insert(keyCode)
        return Decision(event: event, swallow: true)
    }

    private mutating func otherInput(at time: TimeInterval, diagnostic: String) -> Decision {
        guard !reportedOtherInput,
              fnIsDown || lastFnChange.map({ time - $0 < 1 }) == true else { return Decision() }
        reportedOtherInput = true
        return Decision(event: .other, diagnostic: diagnostic)
    }
}
