import Foundation

/// Recognises clean taps and double-taps of a modifier key (the Fn/Globe key on the Mac).
///
/// A tap is "clean" when the key goes down and up quickly with no other input in between,
/// so Fn used as a modifier (Fn+arrow, Fn+Delete, Fn+F-keys) never counts.
/// A double-tap is two clean taps where the second press starts soon after the first release.
///
/// Pure value type: feed it events with timestamps (seconds, any monotonic clock).
public struct FnTapDetector: Sendable {
    public struct Configuration: Sendable, Equatable {
        /// Longest press that still counts as a tap.
        public var maxTapDuration: TimeInterval
        /// Longest gap between the first release and the second press of a double-tap.
        public var maxGapBetweenTaps: TimeInterval

        public init(maxTapDuration: TimeInterval = 0.30, maxGapBetweenTaps: TimeInterval = 0.40) {
            self.maxTapDuration = maxTapDuration
            self.maxGapBetweenTaps = maxGapBetweenTaps
        }
    }

    public enum Event: Sendable, Equatable {
        case keyDown(at: TimeInterval)
        case keyUp(at: TimeInterval)
        /// Any other key or modifier activity. Spoils a tap in progress and breaks a pending double-tap.
        case otherInput
    }

    public enum Gesture: Sendable, Equatable {
        case singleTap
        case doubleTap
    }

    public var configuration: Configuration

    private var pressedAt: TimeInterval?
    private var spoiled = false
    private var lastTapReleasedAt: TimeInterval?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Feeds one event; returns a gesture when one completes.
    ///
    /// Every clean tap reports `.singleTap` except the second tap of a pair, which reports `.doubleTap`
    /// instead. After a double-tap the sequence restarts, so a third tap starts a new pair.
    public mutating func handle(_ event: Event) -> Gesture? {
        switch event {
        case .keyDown(let time):
            if pressedAt != nil { return nil } // repeated down without up; ignore
            pressedAt = time
            spoiled = false
            if let released = lastTapReleasedAt, time - released > configuration.maxGapBetweenTaps {
                lastTapReleasedAt = nil
            }
            return nil

        case .keyUp(let time):
            guard let pressed = pressedAt else { return nil }
            pressedAt = nil
            guard !spoiled, time - pressed <= configuration.maxTapDuration else {
                lastTapReleasedAt = nil
                return nil
            }
            if let released = lastTapReleasedAt, pressed - released <= configuration.maxGapBetweenTaps {
                lastTapReleasedAt = nil
                return .doubleTap
            }
            lastTapReleasedAt = time
            return .singleTap

        case .otherInput:
            if pressedAt != nil { spoiled = true }
            lastTapReleasedAt = nil
            return nil
        }
    }

    /// True while the key has been held cleanly (no other input) for at least `duration`.
    /// Used for press-and-hold push-to-talk; the caller polls it after a timer.
    public func isHeld(for duration: TimeInterval, at time: TimeInterval) -> Bool {
        guard let pressed = pressedAt, !spoiled else { return false }
        return time - pressed >= duration
    }

    /// Forgets any partial sequence, e.g. after a tap has been consumed to stop a recording,
    /// so that tap can't become the first half of a double-tap.
    public mutating func reset() {
        lastTapReleasedAt = nil
        spoiled = pressedAt != nil
    }
}
