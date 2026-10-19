import APCore
import APModels
import SwiftUI

struct SettingsView: View {
    @Bindable var app: AppModel

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
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
