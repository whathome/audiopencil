import AppKit
import SwiftUI

@main
struct AudioPencilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Audio Pencil", id: "main") {
            StatusView(app: delegate.app)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(app: delegate.app)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.bootstrap()
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
