import APAudio
import Foundation
import Testing

@MainActor
struct AudioLevelPreviewTests {
    @Test func levelsAreLiveAndLateCallbacksAreIgnoredAfterStop() async {
        let preview = AudioLevelPreview()
        let source = Source()
        #expect(await preview.start(makeCapture: source.makeCapture).value)
        #expect(preview.isMonitoring)
        source.level?(0.6)
        #expect(preview.level == 0.6)
        #expect(preview.hasAudio)
        source.level?(0)
        #expect(preview.hasAudio)
        #expect(await preview.stop().value)
        source.level?(1)
        source.failure?("late failure")
        #expect(preview.level == 0)
        #expect(!preview.hasAudio)
        #expect(!preview.isMonitoring)
        #expect(preview.error == nil)
        #expect(source.stops == 1)
    }

    @Test func switchingWaitsForPendingStartupAndStopsTheOldSource() async {
        let preview = AudioLevelPreview()
        let first = Source(holdsStart: true)
        let second = Source()
        preview.start(makeCapture: first.makeCapture)
        await first.waitForStart()
        let switched = preview.start(makeCapture: second.makeCapture)
        first.level?(1)
        first.failure?("stale source")
        #expect(preview.level == 0)
        #expect(preview.error == nil)
        #expect(second.starts == 0)
        first.finishStart()
        #expect(await switched.value)
        #expect(first.stops == 1)
        #expect(second.starts == 1)
        second.level?(0.3)
        #expect(preview.level == 0.3)
        #expect(await preview.stop().value)
    }

    @Test func stoppingDuringStartupWaitsForCleanup() async {
        let preview = AudioLevelPreview()
        let source = Source(holdsStart: true)
        preview.start(makeCapture: source.makeCapture)
        await source.waitForStart()
        let stopped = preview.stop()
        #expect(!preview.isStarting)
        #expect(!preview.isMonitoring)
        source.finishStart()
        #expect(await stopped.value)
        #expect(source.stops == 1)
        #expect(!preview.isMonitoring)
    }

    @Test func failedStartupReleasesCaptureAndShowsTheError() async {
        let preview = AudioLevelPreview()
        let source = Source()
        source.failsStart = true
        #expect(!(await preview.start(makeCapture: source.makeCapture).value))
        #expect(!preview.isStarting)
        #expect(!preview.isMonitoring)
        #expect(preview.error?.contains("start failed") == true)
        #expect(source.stops == 1)
        #expect(await preview.stop().value)
        #expect(source.stops == 1)
    }

    @Test func failedStopBlocksReplacementAndCanBeRetried() async {
        let preview = AudioLevelPreview()
        let first = Source()
        let second = Source()
        #expect(await preview.start(makeCapture: first.makeCapture).value)
        first.failedStops = 1
        #expect(!(await preview.start(makeCapture: second.makeCapture).value))
        #expect(second.starts == 0)
        #expect(preview.error?.contains("stop failed") == true)
        #expect(await preview.start(makeCapture: second.makeCapture).value)
        #expect(first.stops == 2)
        #expect(second.starts == 1)
        #expect(preview.error == nil)
        #expect(await preview.stop().value)
    }

    @Test func sourceFailureStopsMonitoringAndRetainsItsReason() async {
        let preview = AudioLevelPreview()
        let source = Source()
        #expect(await preview.start(makeCapture: source.makeCapture).value)
        source.failure?("access revoked")
        #expect(!preview.isMonitoring)
        #expect(preview.level == 0)
        #expect(preview.error == "access revoked")
        #expect(await preview.stop().value)
        #expect(source.stops == 1)
    }

    @MainActor
    private final class Source {
        var level: AudioLevelPreview.LevelHandler?
        var failure: AudioLevelPreview.FailureHandler?
        var starts = 0
        var stops = 0
        var failsStart = false
        var failedStops = 0
        private let holdsStart: Bool
        private var startup: CheckedContinuation<Void, Never>?
        private var waiter: CheckedContinuation<Void, Never>?

        init(holdsStart: Bool = false) { self.holdsStart = holdsStart }

        func makeCapture(level: @escaping AudioLevelPreview.LevelHandler, failure: @escaping AudioLevelPreview.FailureHandler) -> AudioLevelPreview.Capture {
            self.level = level
            self.failure = failure
            return AudioLevelPreview.Capture(start: {
                self.starts += 1
                self.waiter?.resume()
                self.waiter = nil
                if self.holdsStart { await withCheckedContinuation { self.startup = $0 } }
                if self.failsStart { throw Failure.start }
            }, stop: {
                self.stops += 1
                if self.failedStops > 0 {
                    self.failedStops -= 1
                    throw Failure.stop
                }
            })
        }

        func waitForStart() async {
            if starts == 0 { await withCheckedContinuation { waiter = $0 } }
        }

        func finishStart() {
            startup?.resume()
            startup = nil
        }
    }

    private enum Failure: LocalizedError {
        case start, stop
        var errorDescription: String? { self == .start ? "start failed" : "stop failed" }
    }
}
