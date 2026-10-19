import APCore
import APModels
import SwiftUI

/// Main window: setup checklist plus live status of the dictation loop. Doubles as onboarding.
struct StatusView: View {
    @Bindable var app: AppModel

    var body: some View {
        Form {
            Section("Permissions") {
                PermissionRow(
                    title: "Microphone",
                    detail: "To hear you while you dictate.",
                    granted: app.permissions.microphone == .granted,
                    action: ("Allow…", { Task { await app.permissions.requestMicrophone() } })
                )
                PermissionRow(
                    title: "Accessibility",
                    detail: "To see the Fn key and paste into the active field. If you rebuilt the app, remove the old entry and add it again.",
                    granted: app.permissions.accessibility,
                    action: ("Open Settings…", { app.permissions.requestAccessibility() })
                )
                PermissionRow(
                    title: "Fn key free",
                    detail: app.permissions.fnKeyIsFree
                        ? "“Press 🌐 key to” is set to Do Nothing."
                        : "“Press 🌐 key to” is set to \(app.permissions.fnKeyActionDescription). Set it to Do Nothing so double-tapping Fn doesn't also trigger that. Also make sure the Dictation shortcut isn't “Press 🌐 twice”.",
                    granted: app.permissions.fnKeyIsFree,
                    action: ("Keyboard Settings…", { app.permissions.openKeyboardSettings() })
                )
                LabeledContent("Input Monitoring") {
                    Text(app.permissions.inputMonitoring ? "Granted" : "Not needed so far")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Hotkey") {
                LabeledContent("Status") {
                    Label(
                        app.hotkeyActive ? "Listening" : "Waiting for Accessibility",
                        systemImage: app.hotkeyActive ? "checkmark.circle.fill" : "hourglass"
                    )
                    .foregroundStyle(app.hotkeyActive ? .green : .orange)
                }
                LabeledContent("Microphone", value: app.currentMicrophoneName)
                LabeledContent("Start", value: "Double-tap Fn")
                LabeledContent("Stop", value: stopDescription)
                LabeledContent("Cancel", value: "Esc")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fn trace")
                    if app.hotkeyTrace.isEmpty {
                        Text("Press Fn to test").foregroundStyle(.secondary)
                    }
                    ForEach(Array(app.hotkeyTrace.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Transcription model") {
                LabeledContent(TranscriptionModelOption.option(for: app.settings.transcriptionModel)?.name ?? app.settings.transcriptionModel) {
                    modelStatus
                }
                if case .failed = app.modelState {
                    Button("Retry") { app.prepareModel() }
                }
            }

            Section("Last dictation") {
                if let report = app.dictation.lastReport {
                    LabeledContent("Result", value: report.outcome)
                    LabeledContent("Audio", value: String(format: "%.1f s", report.audioSeconds))
                    LabeledContent("Stop → text", value: report.stopToText.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))
                    LabeledContent("Stop → paste", value: report.stopToDelivery.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))
                    LabeledContent("Streaming passes", value: "\(report.passes)")
                    Text(report.preview).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                } else {
                    Text("Nothing yet. Double-tap Fn in any text field and start talking.")
                        .foregroundStyle(.secondary)
                }
                if let error = app.dictation.lastError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }

            Section("Memory") {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    LabeledContent("App footprint", value: MemoryFootprint.formatted(MemoryFootprint.currentBytes()))
                }
                LabeledContent("System pressure", value: app.memoryPressure.rawValue.capitalized)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 560)
    }

    private var stopDescription: String {
        var parts = [app.settings.stopGesture.label]
        if app.settings.returnStops { parts.append("Return") }
        return parts.joined(separator: " or ")
    }

    @ViewBuilder
    private var modelStatus: some View {
        switch app.modelState {
        case .idle:
            Text("Not loaded").foregroundStyle(.secondary)
        case .downloading(let fraction):
            HStack {
                ProgressView(value: fraction).frame(width: 120)
                Text("Downloading \(Int(fraction * 100))%").foregroundStyle(.secondary)
            }
        case .loading(let firstTime):
            HStack {
                ProgressView().controlSize(.small)
                Text(firstTime ? "Preparing for this Mac (first time, a minute or two)…" : "Loading…")
                    .foregroundStyle(.secondary)
            }
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(3)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: (String, () -> Void)

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button(action.0, action: action.1)
            }
        }
    }
}
