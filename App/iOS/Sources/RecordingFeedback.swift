import APAudio
import APCore
@preconcurrency import ActivityKit
import AudioToolbox
import Foundation
import UIKit

/// What a recording sounds and feels like: the tricorder cues on start, pause and stop with a haptic, a
/// distinct alert when the microphone goes away, and a gentle heartbeat while the phone is in a pocket.
@MainActor
final class RecordingFeedback {
    enum Heartbeat: String, CaseIterable, Identifiable {
        case off
        case tap
        case doubleTap

        var id: String { rawValue }
    }

    private let cues = CuePlayer()
    private var heartbeatTask: Task<Void, Never>?

    func configure(theme: String, volume: Double) {
        cues.setTheme(CueTheme(rawValue: theme) ?? .tricorder)
        cues.volume = Float(volume)
    }

    func started() {
        cues.play(.start)
        tap(strong: true)
    }

    func paused() {
        cues.play(.stop)
        tap(strong: false)
    }

    func resumed() {
        cues.play(.start)
        tap(strong: false)
    }

    func stopped() {
        cues.play(.stop)
        tap(strong: true)
    }

    /// Something needs attention (AirPods disconnected): unlike any of the cues, and a long buzz.
    func alert() {
        cues.play(.cancel)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    /// A tap every `minutes` while the app isn't on screen (phone locked or in a pocket), so you can tell it's
    /// still recording without looking. Patterns are short on purpose: nothing like a message's buzz.
    func startHeartbeat(_ pattern: Heartbeat, minutes: Int) {
        stopHeartbeat()
        guard pattern != .off else { return }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(minutes, 1) * 60))
                guard !Task.isCancelled, UIApplication.shared.applicationState != .active else { continue }
                await self?.beat(pattern)
            }
        }
    }

    func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func beat(_ pattern: Heartbeat) async {
        AudioServicesPlaySystemSound(Self.pop)
        if pattern == .doubleTap {
            try? await Task.sleep(for: .milliseconds(180))
            AudioServicesPlaySystemSound(Self.pop)
        }
    }

    /// The system's short haptic taps. UIKit's feedback generators only work while the app is on screen;
    /// these also play in the background and while locked (with haptics allowed during recording).
    private static let peek: SystemSoundID = 1519
    private static let pop: SystemSoundID = 1520

    private func tap(strong: Bool) {
        if UIApplication.shared.applicationState == .active {
            UIImpactFeedbackGenerator(style: strong ? .medium : .light).impactOccurred()
        } else {
            AudioServicesPlaySystemSound(strong ? Self.pop : Self.peek)
        }
    }
}

/// The recording's Live Activity: started with the recording (an audio recording intent needs one), kept
/// current on pause and resume, ended on stop.
@MainActor
final class RecordingActivity {
    private var activity: Activity<RecordingAttributes>?

    init() {
        // A crash or a force quit can leave one behind.
        for leftover in Activity<RecordingAttributes>.activities {
            Task { @MainActor in await leftover.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func start(_ state: RecordingAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Log.dictation.notice("Live Activities are off for Audio Pencil")
            return
        }
        do {
            activity = try Activity.request(attributes: RecordingAttributes(), content: .init(state: state, staleDate: nil))
        } catch {
            Log.dictation.error("Couldn't start the Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `alert` lights the screen and shows on the Lock Screen, for things that need attention.
    func update(_ state: RecordingAttributes.ContentState, alert: (title: String, body: String)? = nil) {
        guard let activity else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        let configuration = alert.map {
            AlertConfiguration(title: LocalizedStringResource(stringLiteral: $0.title), body: LocalizedStringResource(stringLiteral: $0.body), sound: .default)
        }
        Task { @MainActor in await activity.update(content, alertConfiguration: configuration) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { @MainActor in await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
