import Foundation

enum DictationIssue: Equatable {
    case microphonePermission
    case microphone(String)
    case transcription(String)
    case rewriteFallback(String)

    enum Recovery: Equatable {
        case permissions, microphone, models, dismiss
    }

    var message: String {
        switch self {
        case .microphonePermission:
            String(localized: "Audio Pencil needs microphone access. Allow it in Settings › Permissions.")
        case .microphone(let detail):
            String(localized: "Couldn't start the microphone: \(detail)")
        case .transcription(let detail):
            String(localized: "Transcription failed: \(detail)")
        case .rewriteFallback(let detail):
            String(localized: "The rewrite failed. Your raw transcript is available in Last dictation. \(detail)")
        }
    }

    var recovery: Recovery {
        switch self {
        case .microphonePermission: .permissions
        case .microphone: .microphone
        case .transcription: .models
        case .rewriteFallback: .dismiss
        }
    }

    var isNotice: Bool {
        if case .rewriteFallback = self { return true }
        return false
    }
}
