import APCore
import APModels
import SwiftUI

/// Setup checklist (doubles as onboarding) and diagnostics for the dictation loop.
struct SetupView: View {
    @Bindable var app: AppModel
    /// False inside Settings, which has its own title.
    var showsHeader = true
    /// Inside the Settings page: show its title and tab switcher above the first section.
    var settingsHeader = false

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Microphone",
                    detail: "To hear you while you dictate.",
                    granted: app.permissions.microphone == .granted,
                    action: ("Allow…", { Task { await app.permissions.requestMicrophone() } })
                )
                PermissionRow(
                    title: "Accessibility",
                    detail: "To see the Fn key and paste into the active field.",
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
            } header: {
                VStack(alignment: .leading, spacing: 18) {
                    if settingsHeader {
                        SettingsHeader(app: app)
                    }
                    if showsHeader {
                        PageHeader(title: "Setup", subtitle: app.needsSetup ? "A few things to finish before the Fn key works." : "Everything's ready. Diagnostics are below.")
                    }
                    Text(app.needsSetup ? "Permissions: a few things to finish before the Fn key works" : "Permissions").font(.headline)
                }
                .padding(.top, showsHeader ? 8 : 0)
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

            Section("Memory") {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    LabeledContent("App footprint", value: MemoryFootprint.formatted(MemoryFootprint.currentBytes()))
                }
                LabeledContent("System pressure", value: app.memoryPressure.rawValue.capitalized)
            }
        }
        .formStyle(.grouped)
        .pageAligned(settingsHeader)
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
