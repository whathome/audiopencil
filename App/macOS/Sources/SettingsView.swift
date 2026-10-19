import APAudio
import APCore
import APModels
import SwiftUI

struct SettingsView: View {
    @Bindable var app: AppModel
    @State private var vocabularyText = ""

    var body: some View {
        Form {
            Section("Dictation hotkey") {
                Picker("Stop with", selection: $app.settings.stopGesture) {
                    ForEach(StopGesture.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Return also stops", isOn: $app.settings.returnStops)
                Toggle("⌃⌥Space starts and stops (for keyboards without Fn)", isOn: $app.settings.fallbackShortcutEnabled)
                LabeledContent("Double-tap speed") {
                    HStack {
                        Slider(value: $app.settings.doubleTapWindow, in: 0.25...0.7, step: 0.05)
                        Text("\(Int(app.settings.doubleTapWindow * 1000)) ms")
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                Toggle(isOn: $app.settings.warmMicOnFirstTap) {
                    Text("Start the mic on the first Fn tap")
                    Text("Recording starts instantly on the second tap. The mic indicator flashes briefly on a lone Fn tap.")
                }
            }

            MicrophonePriorityList(app: app)

            Section {
                TextEditor(text: $vocabularyText)
                    .font(.body)
                    .frame(minHeight: 70)
                    .onChange(of: vocabularyText) { _, text in
                        app.settings.customVocabulary = text
                            .split(whereSeparator: \.isNewline)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
            } header: {
                Text("Custom vocabulary")
            } footer: {
                Text("One name, place or term per line. Whisper gets them as spelling hints.")
            }

            Section("Transcription") {
                Picker("Model", selection: $app.settings.transcriptionModel) {
                    ForEach(TranscriptionModelOption.catalogue) { option in
                        Text("\(option.name) – \(option.note)").tag(option.id)
                    }
                }
                .disabled(app.dictation.isActive)
                Toggle("Show live transcript above the indicator", isOn: $app.settings.showLiveText)
            }

            Section("App") {
                Toggle(isOn: $app.settings.menuBarMode) {
                    Text("Menu bar only")
                    Text("Hide the Dock icon and show Audio Pencil in the menu bar.")
                }
                Toggle("Launch at login", isOn: Binding(get: { app.launchAtLogin }, set: { app.setLaunchAtLogin($0) }))
                if app.launchAtLoginNeedsApproval {
                    Text("Approve Audio Pencil in System Settings › General › Login Items.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .frame(minHeight: 600)
        .onAppear { vocabularyText = app.settings.customVocabulary.joined(separator: "\n") }
    }
}

/// Ordered list of preferred microphones; the first connected one is used.
private struct MicrophonePriorityList: View {
    @Bindable var app: AppModel

    var body: some View {
        Section {
            let preferences = app.settings.preferredMicrophones
            if preferences.isEmpty {
                Text("No preferences: using the system default input.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(preferences.enumerated()), id: \.element.uid) { index, preference in
                let connected = app.microphones.first { $0.id == preference.uid }
                HStack {
                    Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                    Image(systemName: icon(for: connected?.transport))
                        .frame(width: 18)
                    Text(preference.name)
                    if connected == nil {
                        Text("not connected").font(.caption).foregroundStyle(.secondary)
                    } else if app.currentMicrophone?.id == preference.uid {
                        Text("in use").font(.caption).foregroundStyle(.green)
                    }
                    Spacer()
                    Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(index == 0)
                    Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(index == preferences.count - 1)
                    Button { app.settings.preferredMicrophones.remove(at: index) } label: { Image(systemName: "minus.circle") }
                }
                .buttonStyle(.borderless)
            }
            let addable = app.microphones.filter { mic in !preferences.contains { $0.uid == mic.id } }
            Menu("Add Microphone") {
                ForEach(addable) { mic in
                    Button(mic.name) {
                        app.settings.preferredMicrophones.append(MicrophonePreference(uid: mic.id, name: mic.name))
                    }
                }
            }
            .disabled(addable.isEmpty)
            .fixedSize()
        } header: {
            Text("Microphones")
        } footer: {
            Text("Uses the first connected microphone in this list, otherwise the system default. Now: \(app.currentMicrophoneName).")
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard app.settings.preferredMicrophones.indices.contains(target) else { return }
        app.settings.preferredMicrophones.swapAt(index, target)
    }

    private func icon(for transport: Microphone.Transport?) -> String {
        switch transport {
        case .builtIn: "laptopcomputer"
        case .bluetooth: "airpodspro"
        case .usb: "cable.connector"
        case .other: "mic"
        case nil: "mic.slash"
        }
    }
}
