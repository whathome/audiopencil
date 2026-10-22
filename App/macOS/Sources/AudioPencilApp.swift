import AppKit
import SwiftUI

@main
struct AudioPencilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Audio Pencil", id: "main") {
            MainWindow(app: delegate.app)
        }
        .windowResizability(.contentMinSize)
        .commands {
            // Command-number shortcuts follow the sidebar order.
            CommandGroup(after: .sidebar) {
                Divider()
                ForEach(Array(Page.allCases.enumerated()), id: \.element) { index, page in
                    Button { delegate.app.page = page } label: { Text(page.title) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView(app: delegate.app)
        }

        // SwiftUI writes isInserted back on every scene update. Only assign real changes: any write to
        // `settings` invalidates the scene again, and an unconditional one loops forever on the main thread.
        MenuBarExtra(isInserted: Binding(
            get: { delegate.app.settings.menuBarMode },
            set: { if delegate.app.settings.menuBarMode != $0 { delegate.app.settings.menuBarMode = $0 } }
        )) {
            MenuBarContent(app: delegate.app)
        } label: {
            Image(systemName: delegate.app.dictation.phase == .recording || delegate.app.meetings.ownsCapture ? "waveform.circle.fill" : "pencil.and.scribble")
        }
    }
}

private struct MenuBarContent: View {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusText)
        Button(app.dictation.phase == .recording ? String(localized: "Stop Dictation") : String(localized: "Start Dictation")) {
            app.toggleDictation()
        }
        .disabled(app.dictation.phase == .starting || app.dictation.phase == .finishing || app.meetings.ownsCapture || app.meetings.isProcessing)
        Button("Record a Meeting") {
            openWindow(id: "main")
            app.startMeeting()
        }
            .disabled(app.dictation.phase != .idle)
        if app.meetings.ownsCapture {
            Button(app.meetings.capture == .paused ? "Resume Meeting" : "Pause Meeting") {
                Task { await app.meetings.togglePause() }
            }
            .disabled(app.meetings.capture != .recording && app.meetings.capture != .paused)
            Button("Stop Meeting") { Task { await app.meetings.stop() } }
                .disabled(app.meetings.capture != .recording && app.meetings.capture != .paused)
        }
        Button("Copy Last Dictation") {
            if let text = app.dictation.lastText { app.dictation.paster.copy(text) }
        }
        .disabled(app.dictation.lastText == nil)
        Divider()
        Button("Open Audio Pencil") {
            openWindow(id: "main")
            NSApp.activate()
        }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Audio Pencil") { NSApp.terminate(nil) }
    }

    private var statusText: LocalizedStringResource {
        if app.meetings.ownsCapture {
            return app.meetings.capture == .paused ? "Meeting paused" : "Recording a meeting"
        }
        return switch app.dictation.phase {
        case .recording: "Recording…"
        case .starting, .finishing: "Working…"
        case .idle: app.hotkeyActive ? "Ready: \(app.startHint)" : "Needs Accessibility permission"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Use the bundled icon directly: Launch Services can cache a stale, generic one for builds
        // that were registered before the icon existed.
        if let icon = Bundle.main.image(forResource: "AppIcon") {
            NSApp.applicationIconImage = icon
        }
        app.bootstrap()
    }

    /// A dictation offered on the clipboard on request can't outlive the app: hand over the text.
    func applicationWillTerminate(_ notification: Notification) {
        app.meetings.endPreview()
        app.dictation.paster.settle()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard app.meetings.ownsCapture else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "Stop and save the meeting before quitting?")
        alert.informativeText = String(localized: "Your recording will be saved on this Mac. You can process it next time you open Audio Pencil.")
        alert.addButton(withTitle: String(localized: "Stop, Save and Quit"))
        alert.addButton(withTitle: String(localized: "Keep Recording"))
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        Task {
            app.meetings.processAfterRecording = false
            await app.meetings.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Keep running with no windows open: the hotkey is the main interface.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
