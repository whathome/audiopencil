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
            // ⌘1–⌘6 switch pages, like the sidebar order.
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
            Image(systemName: delegate.app.dictation.phase == .recording ? "waveform.circle.fill" : "pencil.and.scribble")
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
        .disabled(app.dictation.phase == .starting || app.dictation.phase == .finishing)
        Button("Record a Meeting") { app.startMeeting() }
            .disabled(app.dictation.phase != .idle)
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
        switch app.dictation.phase {
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
        app.dictation.paster.settle()
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
