import AppIntents

/// Siri and Shortcuts phrases. Each phrase has to name the app.
struct PhoneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: ["Start recording in \(.applicationName)", "Record a note in \(.applicationName)", "Start \(.applicationName)"],
            shortTitle: "Start Recording",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StopRecordingIntent(),
            phrases: ["Stop recording in \(.applicationName)", "Stop \(.applicationName)"],
            shortTitle: "Stop Recording",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: PauseRecordingIntent(),
            phrases: ["Pause \(.applicationName)", "Pause recording in \(.applicationName)"],
            shortTitle: "Pause Recording",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeRecordingIntent(),
            phrases: ["Resume \(.applicationName)", "Resume recording in \(.applicationName)"],
            shortTitle: "Resume Recording",
            systemImageName: "play.fill"
        )
    }
}
