import APCore
import APModels
import APTranscription
import AVFoundation
import SwiftUI

/// First launch: the microphone, languages, storage and models, in five short steps. The speech model
/// starts downloading on the microphone step, so it's usually ready by the end.
struct PhoneSetupView: View {
    @Bindable var app: PhoneModel
    @State private var step = Step.welcome
    @State private var wantsWriting = true
    @State private var microphoneAllowed = AVAudioApplication.shared.recordPermission == .granted

    enum Step: Int, CaseIterable {
        case welcome, microphone, languages, storage, models
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .microphone: microphone
                case .languages: Form { LanguagesForm(app: app) }
                case .storage: Form { StorageForm(vault: app.vault) }
                case .models: models
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(step == .welcome ? .inline : .large)
            .safeAreaInset(edge: .bottom) { footer }
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { move(-1) }
                    }
                }
            }
        }
    }

    private var title: LocalizedStringResource {
        switch step {
        case .welcome: ""
        case .microphone: "Microphone"
        case .languages: "Languages"
        case .storage: "Where notes go"
        case .models: "Models"
        }
    }

    // MARK: Steps

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image("AppIconImage")
                    .resizable()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio Pencil").font(.system(.largeTitle, design: .serif).bold())
                    Text("Talk it through. Your device writes it up as a note, privately.")
                        .font(.title3).foregroundStyle(.secondary)
                }
                Point(symbol: "waveform", title: "Transcribed as you talk", detail: "Watch the words arrive. Pause when you need to.")
                Point(symbol: "lock", title: "Private by design", detail: "Speech recognition and writing happen on this device. What you say isn't sent anywhere.")
                Point(symbol: "doc.text", title: "Notes in your own folder", detail: "Each recording becomes a Markdown note with its audio, in Obsidian or any folder, on Nextcloud or iCloud Drive.")
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var microphone: some View {
        Form {
            Section {
                if microphoneAllowed {
                    Label("Microphone allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Allow Microphone") {
                        Task { microphoneAllowed = await AVAudioApplication.requestRecordPermission() }
                    }
                }
            } footer: {
                Text("Audio Pencil listens only while you record. The speech model starts downloading now, so it's ready when you are.")
            }
            Section { ModelStatusRow(app: app) }
        }
        .onAppear { app.prepareModel() }
    }

    private var models: some View {
        Form {
            Section {
                LabeledContent("English", value: name(app.settings.transcriptionModel))
                if app.offeredLanguages.contains(where: { !$0.isEnglish }) {
                    LabeledContent("Other languages", value: name(SpeechModels.multilingualTarget(app.settings)))
                }
                ModelStatusRow(app: app)
            } header: {
                Text("Speech")
            } footer: {
                Text("Each is prepared for this device's chip the first time it's used, which takes a few minutes once.")
            }
            Section {
                Toggle(isOn: $wantsWriting) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Write notes in styles with \(app.writingModelOption?.name ?? "the writing model")")
                        Text("Polished text, summaries and key points, plus suggested titles and tags. Without it, notes keep the transcript as spoken.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .disabled(!PhoneModel.canRunWritingModel)
            } header: {
                Text("Writing")
            }
        }
    }

    private var footer: some View {
        Button {
            next()
        } label: {
            Text(primaryTitle).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding()
        .background(.bar)
    }

    private var primaryTitle: LocalizedStringResource {
        switch step {
        case .welcome: "Get Started"
        case .storage: app.vault.settings.isConfigured ? "Continue" : "Skip for Now"
        case .models: "Start Recording"
        default: "Continue"
        }
    }

    private func next() {
        if step == .models {
            if wantsWriting, PhoneModel.canRunWritingModel, !app.writingModelDownloaded { app.downloadWritingModel() }
            app.finishSetup()
        } else {
            move(1)
        }
    }

    private func move(_ delta: Int) {
        if let target = Step(rawValue: step.rawValue + delta) { step = target }
    }

    private func name(_ variant: String) -> String {
        "Whisper " + (TranscriptionModelOption.option(for: variant)?.name ?? variant)
    }

    private struct Point: View {
        let symbol: String
        let title: LocalizedStringResource
        let detail: LocalizedStringResource

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Image(systemName: symbol).foregroundStyle(Color.pencil).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).foregroundStyle(.secondary)
                }
            }
        }
    }
}
