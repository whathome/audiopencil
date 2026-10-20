import APCore
import APModels
import APTranscription
import Foundation
import UserNotifications

/// First-time model preparation (Core ML compiling for this Mac): minutes of work in a system process,
/// so the app shows a step, a running clock and an estimate everywhere it matters, keeps macOS from
/// throttling it, and says when it's done.
extension AppModel {
    /// Which model is being prepared, for the person reading the status.
    func preparationTitle(_ preparation: ModelPreparation) -> String {
        let name = TranscriptionModelOption.option(for: preparation.variant)?.name ?? preparation.variant
        return String(localized: "Preparing Whisper \(name) for this Mac")
    }

    /// Hooks an engine's preparation progress up to the app. Call before loading it.
    func observePreparation(of engine: WhisperEngine) async {
        await engine.setPreparationHandler { [weak self] preparation in
            Task { @MainActor in self?.preparationChanged(preparation) }
        }
    }

    /// Dictation is waiting on this preparation (it's the model in use), rather than it running in the background.
    func isBlocking(_ preparation: ModelPreparation) -> Bool {
        preparation.variant == whisper.variant
    }

    private func preparationChanged(_ new: ModelPreparation?) {
        let finished = preparation
        preparation = new
        indicator.preparation = new.flatMap { isBlocking($0) ? $0 : nil }
        if new != nil, preparationActivity == nil {
            // Keep App Nap from slowing the app down while it waits on the compiler.
            preparationActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Preparing a speech model for this Mac"
            )
        }
        if new == nil {
            if let activity = preparationActivity { ProcessInfo.processInfo.endActivity(activity) }
            preparationActivity = nil
            if let finished, Date().timeIntervalSince(finished.startedAt) > 30 { notifyPrepared(finished) }
        }
    }

    private func notifyPrepared(_ preparation: ModelPreparation) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        let multilingual = preparation.variant == settings.multilingualTranscriptionModel && preparation.variant != settings.transcriptionModel
        content.title = multilingual
            ? String(localized: "Dictation in your other languages is ready")
            : String(localized: "Dictation is ready")
        content.body = String(localized: "The speech model is prepared for this Mac. This only happens once.")
        center.add(UNNotificationRequest(identifier: "prepared-\(preparation.variant)", content: content, trigger: nil))
    }
}
