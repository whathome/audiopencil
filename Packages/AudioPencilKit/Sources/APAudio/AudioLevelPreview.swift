import APCore
import Foundation
import Observation

@MainActor
@Observable
public final class AudioLevelPreview {
    public typealias LevelHandler = @MainActor @Sendable (Float) -> Void
    public typealias FailureHandler = @MainActor @Sendable (String) -> Void
    public typealias MakeCapture = @MainActor (@escaping LevelHandler, @escaping FailureHandler) -> Capture

    public struct Capture {
        fileprivate let start: @MainActor () async throws -> Void
        fileprivate let stop: @MainActor () async throws -> Void

        public init(start: @escaping @MainActor () async throws -> Void, stop: @escaping @MainActor () async throws -> Void) {
            self.start = start
            self.stop = stop
        }
    }

    public private(set) var level: Float = 0
    public private(set) var isStarting = false
    public private(set) var isMonitoring = false
    public private(set) var hasAudio = false
    public private(set) var error: String?
    @ObservationIgnored private var capture: Capture?
    @ObservationIgnored private var operation: Task<Bool, Never>?
    @ObservationIgnored private var request = UUID()

    public init() {}

    @discardableResult
    public func start(makeCapture: @escaping MakeCapture) -> Task<Bool, Never> {
        error = nil
        return transition(to: makeCapture)
    }

    @discardableResult
    public func stop() -> Task<Bool, Never> {
        transition(to: nil)
    }

    private func transition(to makeCapture: MakeCapture?) -> Task<Bool, Never> {
        let id = UUID()
        request = id
        level = 0
        hasAudio = false
        isMonitoring = false
        isStarting = makeCapture != nil
        let previous = operation
        previous?.cancel()
        let task = Task { [weak self] in
            // Native capture startup may ignore cancellation. Let it finish before stopping or replacing it.
            _ = await previous?.value
            guard let self else { return true }
            if let capture {
                do {
                    try await capture.stop()
                    self.capture = nil
                } catch {
                    if request == id {
                        isStarting = false
                        report(String(localized: "Couldn't stop the audio preview: \(error.localizedDescription)", bundle: .module))
                    }
                    return false
                }
            }
            guard request == id, !Task.isCancelled, let makeCapture else { return true }
            let capture = makeCapture({ [weak self] level in
                guard let self, request == id else { return }
                self.level = min(1, max(0, level))
                if level > 0.01 { hasAudio = true }
            }, { [weak self] message in
                guard let self, request == id else { return }
                stop()
                report(message)
            })
            self.capture = capture
            do { try await capture.start() }
            catch {
                var message = String(localized: "Audio preview failed: \(error.localizedDescription)", bundle: .module)
                do {
                    try await capture.stop()
                    self.capture = nil
                } catch {
                    message += "\n" + String(localized: "Couldn't stop the audio preview: \(error.localizedDescription)", bundle: .module)
                }
                if request == id {
                    isStarting = false
                    level = 0
                    hasAudio = false
                    report(message)
                }
                return false
            }
            guard request == id, !Task.isCancelled else { return true }
            isStarting = false
            isMonitoring = true
            return true
        }
        operation = task
        return task
    }

    private func report(_ message: String) {
        error = message
        Log.audio.error("Audio preview: \(message, privacy: .public)")
    }
}
