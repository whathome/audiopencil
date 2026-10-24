import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

@Observable
final class Permissions {
    enum MicrophoneStatus {
        case granted, denied, notDetermined
    }

    private(set) var microphone: MicrophoneStatus = .notDetermined
    private(set) var accessibility = false
    /// Optional for dictation; ScreenCaptureKit needs this to capture the call app's audio.
    private(set) var onlineMeetingAudio = false
    /// System Settings › Keyboard › "Press 🌐 key to": 0 Do Nothing, 1 Change Input Source,
    /// 2 Show Emoji & Symbols, 3 Start Dictation.
    private(set) var fnKeyAction: Int?

    var allRequiredGranted: Bool { microphone == .granted && accessibility }
    var fnKeyIsFree: Bool { (fnKeyAction ?? 0) == 0 }

    var fnKeyActionDescription: String {
        switch fnKeyAction ?? 0 {
        case 0: String(localized: "Do Nothing")
        case 1: String(localized: "Change Input Source")
        case 2: String(localized: "Show Emoji & Symbols")
        case 3: String(localized: "Start Dictation")
        default: String(localized: "Unknown")
        }
    }

    func refresh() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphone = .granted
        case .notDetermined: microphone = .notDetermined
        default: microphone = .denied
        }
        accessibility = AXIsProcessTrusted()
        onlineMeetingAudio = CGPreflightScreenCaptureAccess()
        fnKeyAction = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString) as? Int
    }

    func requestMicrophone() async {
        if microphone == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            Self.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        }
        refresh()
    }

    func requestAccessibility() {
        // Adds the app to the Accessibility list and shows the system prompt.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            Self.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
        refresh()
    }

    func requestOnlineMeetingAudio() {
        if !CGRequestScreenCaptureAccess() {
            Self.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
        refresh()
    }

    func openKeyboardSettings() {
        Self.openSettings("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    private static func openSettings(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}
