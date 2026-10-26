import APCore
import CoreGraphics
import Foundation
import Synchronization
import Testing

nonisolated struct HotkeyMonitorTests {
    private func capturingProcessor() -> HotkeyEventProcessor {
        var processor = HotkeyEventProcessor()
        processor.policy = .init(swallowEscape: true, swallowReturn: true, swallowDigits: true, swallowShortcut: true)
        return processor
    }

    @Test func ordinaryTypingDoesNotReachTheUIOrGetSwallowed() {
        var processor = capturingProcessor()
        for index in 0..<10_000 {
            let decision = processor.process(type: .keyDown, keyCode: 0, at: Double(index))
            #expect(decision.event == nil)
            #expect(decision.diagnostic == nil)
            #expect(!decision.swallow)
        }
    }

    @Test func recordingControlsAndTheirMatchingReleasesAreSwallowed() {
        let controls: [(Int64, HotkeyEventProcessor.KeyEvent)] = [
            (53, .escape), (36, .returnKey), (76, .returnKey), (18, .digit(1)), (82, .digit(0)),
        ]
        for (keyCode, expected) in controls {
            var processor = capturingProcessor()
            let down = processor.process(type: .keyDown, keyCode: keyCode, at: 1)
            #expect(down.event == expected)
            #expect(down.swallow)
            let repeated = processor.process(type: .keyDown, keyCode: keyCode, isRepeat: true, at: 1.1)
            #expect(repeated.swallow)
            #expect(repeated.event == nil)
            processor.policy = .init()
            #expect(processor.process(type: .keyUp, keyCode: keyCode, at: 1.2).swallow)
            #expect(!processor.process(type: .keyUp, keyCode: keyCode, at: 1.3).swallow)
        }
    }

    @Test func idleControlsAndModifiedTypingPassThrough() {
        var processor = HotkeyEventProcessor()
        for keyCode in [Int64(53), 36, 76, 18, 82] {
            let decision = processor.process(type: .keyDown, keyCode: keyCode, at: 1)
            #expect(!decision.swallow)
            #expect(decision.event == nil)
        }
        processor = capturingProcessor()
        #expect(!processor.process(type: .keyDown, keyCode: 36, flags: .maskCommand, at: 2).swallow)
        #expect(!processor.process(type: .keyDown, keyCode: 18, flags: .maskControl, at: 2).swallow)
    }

    @Test func fallbackShortcutOnlyCapturesTheConfiguredModifiers() {
        var processor = capturingProcessor()
        let shortcut = KeyShortcut.controlOptionSpace
        let down = processor.process(type: .keyDown, keyCode: Int64(shortcut.keyCode),
                                     flags: CGEventFlags(rawValue: shortcut.modifiers), at: 1)
        #expect(down.event == .fallbackShortcut)
        #expect(down.swallow)
        #expect(processor.process(type: .keyUp, keyCode: Int64(shortcut.keyCode), at: 1.1).swallow)
        #expect(!processor.process(type: .keyDown, keyCode: Int64(shortcut.keyCode), at: 2).swallow)
    }

    @Test func fnGesturesAndModifierUseAreDeliveredInOrder() {
        var processor = HotkeyEventProcessor()
        #expect(processor.process(type: .flagsChanged, keyCode: 63, flags: .maskSecondaryFn, at: 1).event == .fnDown)
        #expect(processor.process(type: .keyDown, keyCode: 0, flags: .maskSecondaryFn, at: 1.1).event == .other)
        #expect(processor.process(type: .keyDown, keyCode: 0, flags: .maskSecondaryFn, at: 1.2).event == nil)
        #expect(processor.process(type: .flagsChanged, keyCode: 63, at: 1.3).event == .fnUp)
        #expect(processor.process(type: .keyDown, keyCode: 179, at: 1.31).event == nil)
        #expect(processor.process(type: .keyDown, keyCode: 0, at: 1.4).event == .other)
    }

    @Test func alternativeGestureKeysKeepTheirDeviceSpecificFlags() {
        let gestures: [(GestureKey, UInt64)] = [(.rightOption, 0x40), (.rightCommand, 0x10)]
        for (key, flag) in gestures {
            var processor = HotkeyEventProcessor()
            processor.gestureKey = key
            #expect(processor.process(type: .flagsChanged, keyCode: 0, flags: .init(rawValue: flag), at: 1).event == .fnDown)
            #expect(processor.process(type: .flagsChanged, keyCode: 0, at: 1.1).event == .fnUp)
        }
    }

    @Test func pausedDisabledAndSyntheticEventsPassThrough() {
        var processor = capturingProcessor()
        #expect(!processor.process(type: .keyDown, keyCode: 53, isSynthetic: true, at: 1).swallow)
        processor.isPaused = true
        #expect(!processor.process(type: .keyDown, keyCode: 53, at: 2).swallow)
        #expect(processor.process(type: .flagsChanged, keyCode: 63, flags: .maskSecondaryFn, at: 2).event == nil)
        processor.isPaused = false
        processor.policy.isEnabled = false
        #expect(!processor.process(type: .keyDown, keyCode: 53, at: 3).swallow)
    }

    @Test func pausingDoesNotLeakAnAlreadySwallowedRelease() {
        var processor = capturingProcessor()
        #expect(processor.process(type: .keyDown, keyCode: 53, at: 1).swallow)
        processor.isPaused = true
        #expect(processor.process(type: .keyUp, keyCode: 53, at: 2).swallow)
    }

    @Test func timeoutPermanentlyFailsOpenEvenAfterConfigurationChanges() {
        var processor = capturingProcessor()
        #expect(processor.process(type: .keyDown, keyCode: 53, at: 1).swallow)
        #expect(processor.process(type: .tapDisabledByTimeout, keyCode: 0, at: 2).tapTimedOut)
        #expect(processor.hasTimedOut)
        #expect(!processor.process(type: .tapDisabledByTimeout, keyCode: 0, at: 3).tapTimedOut)
        processor.policy = .init(swallowEscape: true, swallowReturn: true, swallowDigits: true, swallowShortcut: true)
        processor.isPaused = false
        processor.gestureKey = .rightOption
        for type in [CGEventType.keyDown, .keyUp, .flagsChanged, .tapDisabledByUserInput] {
            for keyCode in [Int64(0), 53, 36, 18, 49] {
                let decision = processor.process(type: type, keyCode: keyCode, flags: .init(rawValue: 0x40), at: 4)
                #expect(!decision.swallow)
                #expect(decision.event == nil)
                #expect(!decision.tapTimedOut)
            }
        }
    }

    @Test @MainActor func timeoutNotifiesTheUIOnceAndCannotBeRearmedByUserInput() async {
        let deliveries = HotkeyDeliveries()
        let context = HotkeyTapContext(processor: capturingProcessor()) { decision, _ in
            if decision.tapTimedOut { deliveries.timeouts += 1 }
            if let event = decision.event { deliveries.events.append(event) }
        }
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true)!
        event.flags = []
        context.handleTimeout()
        context.handleTimeout()
        #expect(!context.process(type: .tapDisabledByUserInput, event: event))
        #expect(!context.process(type: .keyDown, event: event))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(deliveries.timeouts == 1)
        #expect(deliveries.events.isEmpty)
    }

    @Test @MainActor func timeoutStopsCapturingBeforeTheMainActorCanRespond() {
        let deliveries = HotkeyDeliveries()
        let context = HotkeyTapContext(processor: capturingProcessor()) { decision, _ in
            if decision.tapTimedOut { deliveries.timeouts += 1 }
        }
        let completed = DispatchSemaphore(value: 0)
        let swallowed = Mutex(true)
        DispatchQueue.global(qos: .userInteractive).async {
            context.handleTimeout()
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true)!
            event.flags = []
            swallowed.withLock { $0 = context.process(type: .keyDown, event: event) }
            completed.signal()
        }
        #expect(completed.wait(timeout: .now() + 1) == .success)
        #expect(!swallowed.withLock { $0 })
        #expect(deliveries.timeouts == 0)
    }

    @Test @MainActor func callbackReturnsWhileTheMainActorIsBlocked() {
        let deliveries = HotkeyDeliveries()
        let context = HotkeyTapContext(processor: capturingProcessor()) { decision, _ in
            if let event = decision.event { deliveries.events.append(event) }
        }
        let completed = DispatchSemaphore(value: 0)
        let swallowed = Mutex(false)
        DispatchQueue.global(qos: .userInteractive).async {
            let ordinary = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
            ordinary.flags = []
            for _ in 0..<1_000 { _ = context.process(type: .keyDown, event: ordinary) }
            let control = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true)!
            control.flags = []
            swallowed.withLock { $0 = context.process(type: .keyDown, event: control) }
            completed.signal()
        }
        // Deliberately block the UI actor: global input must not need it to return an event.
        #expect(completed.wait(timeout: .now() + 1) == .success)
        #expect(swallowed.withLock { $0 })
        #expect(deliveries.events.isEmpty)
    }
}

@MainActor private final class HotkeyDeliveries {
    var events: [HotkeyEventProcessor.KeyEvent] = []
    var timeouts = 0
}
