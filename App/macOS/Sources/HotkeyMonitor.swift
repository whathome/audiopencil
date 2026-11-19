import AppKit
import APCore
import CoreGraphics
import Synchronization

/// Global keyboard input is serviced independently of the UI. Only completed decisions reach the main actor.
final class HotkeyMonitor {
    typealias KeyEvent = HotkeyEventProcessor.KeyEvent
    typealias Policy = HotkeyEventProcessor.Policy
    nonisolated static let syntheticMarker = HotkeyEventProcessor.syntheticMarker

    var handler: ((KeyEvent, TimeInterval) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onTimeout: (() -> Void)?
    private(set) var isActive = false
    private(set) var hasTimedOut = false
    var gestureKey: GestureKey = .fn { didSet { updateConfiguration() } }
    var shortcut: KeyShortcut = .controlOptionSpace { didSet { updateConfiguration() } }
    var isPaused = false { didSet { updateConfiguration() } }
    var policy = Policy() { didSet { updateConfiguration() } }
    private var context: HotkeyTapContext?
    private var generation: UUID?

    deinit { context?.stop() }

    @discardableResult
    func start() -> Bool {
        guard !hasTimedOut else { return false }
        guard context == nil else { return true }
        let generation = UUID()
        self.generation = generation
        var processor = HotkeyEventProcessor()
        processor.gestureKey = gestureKey
        processor.shortcut = shortcut
        processor.isPaused = isPaused
        processor.policy = policy
        let context = HotkeyTapContext(processor: processor) { [weak self] decision, time in
            guard let self, self.generation == generation, self.isActive else { return }
            if decision.tapTimedOut {
                self.hasTimedOut = true
                self.stop()
                Log.hotkey.error("Keyboard event tap timed out; shortcuts paused until relaunch to protect system input")
                self.onTimeout?()
                return
            }
            if let diagnostic = decision.diagnostic { self.onDiagnostic?(diagnostic) }
            if let event = decision.event { self.handler?(event, time) }
        }
        guard context.start() else { self.generation = nil; return false }
        self.context = context
        isActive = true
        Log.hotkey.notice("Event tap active on its dedicated input thread")
        return true
    }

    func stop() {
        generation = nil
        context?.stop()
        context = nil
        isActive = false
    }

    #if DEBUG
    func simulateTimeout() {
        context?.handleTimeout()
    }
    #endif

    private func updateConfiguration() {
        context?.configure(gestureKey: gestureKey, shortcut: shortcut, isPaused: isPaused, policy: policy)
    }
}

/// Mutable input decisions are mutex-protected; run-loop ownership is protected separately.
nonisolated final class HotkeyTapContext: @unchecked Sendable {
    private let processor: Mutex<HotkeyEventProcessor>
    private let deliver: @MainActor @Sendable (HotkeyEventProcessor.Decision, TimeInterval) -> Void
    private let lifecycle = NSLock()
    private var runLoop: CFRunLoop?
    private var stopped = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    init(
        processor: HotkeyEventProcessor,
        deliver: @escaping @MainActor @Sendable (HotkeyEventProcessor.Decision, TimeInterval) -> Void
    ) {
        self.processor = Mutex(processor)
        self.deliver = deliver
    }

    func configure(gestureKey: GestureKey, shortcut: KeyShortcut, isPaused: Bool, policy: HotkeyEventProcessor.Policy) {
        processor.withLock {
            $0.gestureKey = gestureKey
            $0.shortcut = shortcut
            $0.isPaused = isPaused
            $0.policy = policy
        }
    }

    func start() -> Bool {
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.hotkey.error("Couldn't create event tap (Accessibility not granted?)")
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            Log.hotkey.error("Couldn't create the keyboard input run-loop source")
            return false
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        self.tap = tap
        self.source = source
        let thread = Thread { [self] in
            guard let tap = self.tap, let source = self.source else { return }
            let loop = CFRunLoopGetCurrent()
            lifecycle.lock()
            let shouldStop = stopped
            if !shouldStop { runLoop = loop }
            lifecycle.unlock()
            guard !shouldStop else { return }
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFMachPortInvalidate(tap)
            lifecycle.lock()
            runLoop = nil
            lifecycle.unlock()
        }
        thread.name = "AudioPencil.Hotkeys"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    func stop() {
        lifecycle.lock()
        stopped = true
        let loop = runLoop
        lifecycle.unlock()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let loop {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(loop) }
            CFRunLoopWakeUp(loop)
        }
    }

    func process(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout {
            handleTimeout()
            return false
        }
        if type == .tapDisabledByUserInput {
            lifecycle.lock()
            let shouldEnable = !stopped
            lifecycle.unlock()
            if shouldEnable, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                DispatchQueue.main.async {
                    Log.hotkey.notice("Keyboard event tap disabled by user input; re-enabled on the input thread")
                }
            }
            return false
        }
        let time = ProcessInfo.processInfo.systemUptime
        let decision = processor.withLock {
            $0.process(
                type: type, keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                isSynthetic: event.getIntegerValueField(.eventSourceUserData) == HotkeyEventProcessor.syntheticMarker,
                at: time
            )
        }
        if decision.event != nil || decision.diagnostic != nil {
            let deliver = self.deliver
            DispatchQueue.main.async { deliver(decision, time) }
        }
        return decision.swallow
    }

    func handleTimeout() {
        let time = ProcessInfo.processInfo.systemUptime
        let decision = processor.withLock {
            $0.process(type: .tapDisabledByTimeout, keyCode: 0, at: time)
        }
        guard decision.tapTimedOut else { return }
        // WindowServer has already disabled the tap. Never put a failing tap back in the input path.
        stop()
        let deliver = self.deliver
        DispatchQueue.main.async { deliver(decision, time) }
    }
}

private nonisolated func hotkeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<HotkeyTapContext>.fromOpaque(refcon).takeUnretainedValue()
    return context.process(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
