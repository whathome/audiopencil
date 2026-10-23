import APCore
import Foundation
import Testing

struct FnTapDetectorTests {
    private func run(_ events: [FnTapDetector.Event], config: FnTapDetector.Configuration = .init()) -> [FnTapDetector.Gesture] {
        var detector = FnTapDetector(configuration: config)
        return events.compactMap { detector.handle($0) }
    }

    @Test func cleanTapIsSingleTap() {
        #expect(run([.keyDown(at: 0), .keyUp(at: 0.1)]) == [.singleTap])
    }

    @Test func twoQuickTapsMakeDoubleTap() {
        let gestures = run([.keyDown(at: 0), .keyUp(at: 0.08), .keyDown(at: 0.25), .keyUp(at: 0.33)])
        #expect(gestures == [.singleTap, .doubleTap])
    }

    @Test func slowSecondTapIsTwoSingles() {
        let gestures = run([.keyDown(at: 0), .keyUp(at: 0.08), .keyDown(at: 0.9), .keyUp(at: 1.0)])
        #expect(gestures == [.singleTap, .singleTap])
    }

    @Test func longHoldIsNotATap() {
        #expect(run([.keyDown(at: 0), .keyUp(at: 0.6)]).isEmpty)
    }

    @Test func fnUsedAsModifierIsNotATap() {
        // Fn+Delete: another key while Fn is down.
        #expect(run([.keyDown(at: 0), .otherInput, .keyUp(at: 0.1)]).isEmpty)
    }

    @Test func otherKeyBetweenTapsBreaksDoubleTap() {
        let gestures = run([.keyDown(at: 0), .keyUp(at: 0.08), .otherInput, .keyDown(at: 0.2), .keyUp(at: 0.28)])
        #expect(gestures == [.singleTap, .singleTap])
    }

    @Test func thirdTapStartsNewSequence() {
        let gestures = run([
            .keyDown(at: 0), .keyUp(at: 0.05),
            .keyDown(at: 0.15), .keyUp(at: 0.2),
            .keyDown(at: 0.3), .keyUp(at: 0.35),
        ])
        #expect(gestures == [.singleTap, .doubleTap, .singleTap])
    }

    @Test func resetPreventsConsumedTapFromPairing() {
        var detector = FnTapDetector()
        #expect(detector.handle(.keyDown(at: 0)) == nil)
        #expect(detector.handle(.keyUp(at: 0.05)) == .singleTap)
        detector.reset() // that tap stopped a recording
        #expect(detector.handle(.keyDown(at: 0.2)) == nil)
        #expect(detector.handle(.keyUp(at: 0.25)) == .singleTap)
    }

    @Test func cleanHoldIsReported() {
        var detector = FnTapDetector()
        _ = detector.handle(.keyDown(at: 0))
        #expect(!detector.isHeld(for: 0.35, at: 0.2))
        #expect(detector.isHeld(for: 0.35, at: 0.4))
        #expect(detector.handle(.keyUp(at: 1.5)) == nil) // a hold is never a tap
        #expect(!detector.isHeld(for: 0.35, at: 2))
    }

    @Test func holdWithAnotherKeyIsNotAHold() {
        var detector = FnTapDetector()
        _ = detector.handle(.keyDown(at: 0))
        _ = detector.handle(.otherInput) // Fn+arrow
        #expect(!detector.isHeld(for: 0.35, at: 0.5))
    }

    @Test(arguments: [0.1, 0.15, 0.35, 1.0])
    func holdUsesConfiguredDelay(_ delay: Double) {
        var detector = FnTapDetector()
        _ = detector.handle(.keyDown(at: 0))
        #expect(!detector.isHeld(for: delay, at: delay - 0.001))
        #expect(detector.isHeld(for: delay, at: delay))
        _ = detector.handle(.keyUp(at: delay + 0.01))
        detector.reset() // release consumed by push-to-talk, even if it was shorter than a tap
        #expect(!detector.isHeld(for: delay, at: delay + 0.02))
        _ = detector.handle(.keyDown(at: delay + 0.1))
        #expect(detector.handle(.keyUp(at: delay + 0.15)) == .singleTap)
    }

    @Test func gapIsConfigurable() {
        let tight = FnTapDetector.Configuration(maxTapDuration: 0.3, maxGapBetweenTaps: 0.1)
        let gestures = run([.keyDown(at: 0), .keyUp(at: 0.05), .keyDown(at: 0.25), .keyUp(at: 0.3)], config: tight)
        #expect(gestures == [.singleTap, .singleTap])
    }
}

struct DictationSettingsTests {
    @Test func decodesOldPayloadWithDefaults() throws {
        let json = #"{"stopGesture":"doubleTapFn"}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(DictationSettings.self, from: json)
        #expect(settings.stopGesture == .doubleTapFn)
        #expect(settings.returnStops)
        #expect(settings.pushToTalkDelay == 0.35)
        #expect(settings.transcriptionModel == "openai_whisper-small.en")
    }

    @Test func pushToTalkDelayPersists() throws {
        var settings = DictationSettings()
        settings.pushToTalkDelay = 0.15
        let restored = try JSONDecoder().decode(DictationSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored == settings)
    }

    @Test(arguments: [-1.0, 0.0, 0.1, 0.15, 0.35, 1.0, 10.0])
    func pushToTalkDelayIsBounded(_ delay: Double) throws {
        let json = Data("{\"pushToTalkDelay\":\(delay)}".utf8)
        let settings = try JSONDecoder().decode(DictationSettings.self, from: json)
        #expect(settings.pushToTalkDelay == min(max(delay, 0.1), 1.0))
    }
}
