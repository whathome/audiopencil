import APCore
import APModels
import AppKit
import SwiftUI

/// Styles: what each number key does while recording, editable prompts, and per-app defaults.
struct StylesPage: View {
    @Bindable var app: AppModel
    @State private var editing: Style?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Styles", subtitle: "Double-tap Fn to dictate in a style. Press its number while you talk to switch.")

                WritingModelBanner(app: app)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    ForEach(sortedStyles) { style in
                        StyleCard(style: style, isDefault: style.id == app.styleMemory.lastUsed, sampleCount: app.writingSamples.count) {
                            editing = style
                        } toggle: { enabled in
                            update(style.id) { $0.isEnabled = enabled }
                        }
                    }
                }

                HStack {
                    Button {
                        let style = newStyle()
                        app.styles.append(style)
                        editing = style
                    } label: {
                        Label("New style", systemImage: "plus")
                    }
                    Spacer()
                }

                PerAppDefaults(app: app)
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .sheet(item: $editing) { style in
            StyleEditor(
                style: style,
                takenShortcuts: Set(app.styles.filter { $0.id != style.id }.compactMap(\.shortcut)),
                isPreset: Style.presets.contains { $0.id == style.id },
                save: { edited in update(style.id) { $0 = edited } },
                reset: { app.resetStyle(style.id) },
                delete: { app.styles.removeAll { $0.id == style.id } }
            )
        }
    }

    private var sortedStyles: [Style] {
        app.styles.sorted { ($0.shortcut ?? 99, $0.name) < ($1.shortcut ?? 99, $1.name) }
    }

    private func update(_ id: String, _ change: (inout Style) -> Void) {
        guard let index = app.styles.firstIndex(where: { $0.id == id }) else { return }
        change(&app.styles[index])
    }

    private func newStyle() -> Style {
        let taken = Set(app.styles.compactMap(\.shortcut))
        return Style(
            id: "custom-\(UUID().uuidString.prefix(8).lowercased())",
            name: "New style",
            shortcut: (1...9).first { !taken.contains($0) },
            instructions: "Describe what this style should do with what you say.",
            intensity: .moderate, tone: .asSpoken, length: .asSpoken
        )
    }
}

private struct StyleCard: View {
    let style: Style
    let isDefault: Bool
    var sampleCount = 0
    let edit: () -> Void
    let toggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                KeyCap(label: style.shortcut.map(String.init) ?? "–")
                Text(style.name).font(.headline)
                if isDefault {
                    Text("Last used").font(.caption2.weight(.semibold)).foregroundStyle(Color.pencil)
                }
                Spacer()
                if !style.isRaw {
                    Toggle("", isOn: Binding(get: { style.isEnabled }, set: toggle))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .disabled(style.tone == .likeMe && sampleCount < InterviewPrompt.minimumSamples)
                }
            }
            Text(style.isRaw ? "Pastes exactly what you said. Holding Fn always gives you this." : style.instructions)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if style.isRaw {
                    Tag("No writing model")
                } else {
                    Tag(style.intensity.label)
                    if style.tone != .asSpoken { Tag(style.tone.label) }
                    if style.length != .asSpoken { Tag(style.length.label) }
                }
                if style.tone == .likeMe {
                    Tag(sampleCount < InterviewPrompt.minimumSamples ? "Needs \(InterviewPrompt.minimumSamples) writing samples (My writing)" : "\(sampleCount) writing samples")
                }
                Spacer()
                if !style.isRaw {
                    Button("Edit", action: edit).buttonStyle(.link)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        .opacity(style.isEnabled ? 1 : 0.6)
    }
}

private struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.14)))
    }
}

private struct StyleEditor: View {
    @State var style: Style
    let takenShortcuts: Set<Int>
    let isPreset: Bool
    let save: (Style) -> Void
    let reset: () -> Void
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $style.name)
                Picker("Number key", selection: $style.shortcut) {
                    Text("None").tag(Int?.none)
                    ForEach(1...9, id: \.self) { number in
                        Text(takenShortcuts.contains(number) ? "\(number) (in use)" : "\(number)")
                            .tag(Int?.some(number))
                    }
                }
                Section("What it does") {
                    TextEditor(text: $style.instructions)
                        .font(.body)
                        .frame(minHeight: 110)
                }
                Section("Shape") {
                    Picker("Rewrite", selection: $style.intensity) {
                        ForEach(Style.Intensity.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Tone", selection: $style.tone) {
                        ForEach(Style.Tone.allCases.filter { $0 != .likeMe }, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Length", selection: $style.length) {
                        ForEach(Style.Length.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Toggle("Enabled", isOn: $style.isEnabled)
                }
                Section {
                    TextField("Folder in the vault", text: Binding(
                        get: { style.folder ?? "" },
                        set: { style.folder = $0.isEmpty ? nil : $0 }
                    ), prompt: Text(String(NoteMaker.defaultFolder.dropFirst())))
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Where long recordings (and saved quick dictations) in this style land.")
                }
            }
            .formStyle(.grouped)

            HStack {
                if isPreset {
                    Button("Reset to default") { reset(); dismiss() }
                } else {
                    Button("Delete style", role: .destructive) { delete(); dismiss() }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(style)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(style.name.trimmingCharacters(in: .whitespaces).isEmpty || style.shortcut.map(takenShortcuts.contains) == true)
            }
            .padding(16)
        }
        .frame(width: 520, height: 600)
    }
}

/// Shows whether the writing model is on disk, with a download button.
struct WritingModelBanner: View {
    let app: AppModel

    var body: some View {
        let option = app.writingModelOption
        let size = option.map { String(format: "%.1f GB", $0.approximateDownloadGB) } ?? "about 2 GB"
        switch app.writingModelState {
        case .downloading(let fraction):
            Card {
                HStack {
                    Image(systemName: "arrow.down.circle").foregroundStyle(Color.pencil)
                    Text("Downloading \(option?.name ?? "writing model")…")
                    ProgressView(value: fraction).frame(maxWidth: 220)
                    Text("\(Int(fraction * 100))%").monospacedDigit().foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            Banner(symbol: "exclamationmark.triangle.fill", message: "Download failed: \(message)", actionTitle: "Retry") {
                app.downloadWritingModel()
            }
        default:
            if !app.writingModelDownloaded {
                Banner(symbol: "arrow.down.circle", message: "Styles need the writing model, \(option?.name ?? "") (\(size), downloads once). Until then, dictations paste raw.", actionTitle: "Download") {
                    app.downloadWritingModel()
                }
            }
        }
    }
}

private struct PerAppDefaults: View {
    @Bindable var app: AppModel

    var body: some View {
        Card(title: "Per-app defaults") {
            let entries = app.styleMemory.perApp.sorted { $0.key < $1.key }
            if entries.isEmpty {
                Text("Audio Pencil remembers the style you use in each app and starts there next time.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(entries, id: \.key) { bundleID, styleID in
                HStack {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                        Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                    } else {
                        Text(bundleID)
                    }
                    Spacer()
                    Text(app.styles.first { $0.id == styleID }?.name ?? styleID).foregroundStyle(.secondary)
                    Button {
                        app.styleMemory.forget(app: bundleID)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .help("Forget this app's default")
                }
            }
        }
    }
}

extension Style.Intensity {
    var label: String {
        switch self {
        case .light: "Light tidy"
        case .moderate: "Rewrite"
        case .heavy: "Restructure"
        }
    }
}

extension Style.Tone {
    var label: String {
        switch self {
        case .asSpoken: "As spoken"
        case .casual: "Casual"
        case .professional: "Professional"
        case .business: "Business"
        case .likeMe: "Like me"
        }
    }
}

extension Style.Length {
    var label: String {
        switch self {
        case .asSpoken: "Same length"
        case .shorter: "Shorter"
        case .brief: "Brief"
        }
    }
}
