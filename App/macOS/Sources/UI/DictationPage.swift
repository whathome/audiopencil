import APCore
import APModels
import SwiftUI

/// Home page: how to dictate, what's listening, the last result, and local stats.
struct DictationPage: View {
    let app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Dictation", subtitle: "Talk anywhere. Text lands where you're typing, transcribed on this Mac.")

                if app.needsSetup {
                    Banner(symbol: "exclamationmark.triangle.fill", message: "Finish setup so the hotkey can start dictation.", actionTitle: "Finish setup") {
                        app.openPermissions()
                    }
                }

                // Side by side when there's room; stats move underneath, in a grid, when narrow.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        cards.frame(minWidth: 460, maxWidth: .infinity)
                        StatsColumn(stats: app.stats).frame(width: 210)
                    }
                    VStack(spacing: 16) {
                        cards
                        StatsColumn(stats: app.stats, columns: 2)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    private var cards: some View {
        // What you said comes first; the reference and the machinery follow.
        VStack(spacing: 16) {
            TryItCard(app: app)
            LastDictationCard(app: app)
            HotkeyCard(app: app)
            TranscriptionCard(app: app)
        }
    }
}

struct PageHeader: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 30, weight: .bold, design: .serif))
            Text(subtitle).font(.title3).foregroundStyle(.secondary)
        }
    }
}

private struct HotkeyCard: View {
    let app: AppModel

    private var key: GestureKey { app.settings.gestureKey }

    var body: some View {
        Card(title: "Hotkey") {
            // One row per gesture, in the order you use them: what it does on the left, the keys on the right.
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GestureRow(
                    title: "Start dictating",
                    detail: app.settings.startGesture == .doubleTap ? "Double-tap; 1–9 picks a style while you talk" : "Tap; 1–9 picks a style while you talk",
                    keys: "\(app.settings.startGesture.label(key))"
                ) {
                    KeyCap(label: "\(key.keycap)")
                    if app.settings.startGesture == .doubleTap { KeyCap(label: "\(key.keycap)") }
                }
                if app.settings.holdFnForRaw {
                    GestureRow(title: "Push to talk", detail: "Hold, release to paste the raw transcript", keys: "Hold \(key.name)") {
                        KeyCap(label: "hold \(key.keycap)")
                    }
                }
                GestureRow(title: "Stop and paste", detail: stopDetail, keys: stopKeys) {
                    KeyCap(label: "\(key.keycap)")
                    if app.settings.effectiveStopGesture == .doubleTapFn { KeyCap(label: "\(key.keycap)") }
                    if app.settings.returnStops { KeyCap(label: "return", symbol: "return") }
                }
                GestureRow(title: "Cancel", detail: "Nothing is pasted", keys: "Escape") {
                    KeyCap(label: "esc")
                }
                if app.settings.fallbackShortcutEnabled {
                    GestureRow(title: "Shortcut", detail: "Also starts and stops", keys: "\(app.settings.fallbackShortcut.displayText)") {
                        KeyCap(label: "\(app.settings.fallbackShortcut.displayText)")
                    }
                }
            }
            HStack {
                Spacer()
                Button("Change…") { app.settingsTab = .general; app.page = .settings }
                    .buttonStyle(.link)
            }
        }
    }

    private var stopKeys: LocalizedStringResource {
        let gesture = app.settings.effectiveStopGesture.label(key)
        return app.settings.returnStops ? "\(gesture) or Return" : "\(gesture)"
    }

    private var stopDetail: LocalizedStringResource {
        switch (app.settings.effectiveStopGesture, app.settings.returnStops) {
        case (.singleTapFn, true): "Tap or Return"
        case (.singleTapFn, false): "Tap"
        case (.doubleTapFn, true): "Double-tap or Return"
        case (.doubleTapFn, false): "Double-tap"
        }
    }
}

/// A gesture: what it does (title, detail) on the left, its keycaps on the right.
private struct GestureRow<Keys: View>: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    /// The keys in words, for VoiceOver (keycaps alone read as "fn fn").
    let keys: LocalizedStringResource
    @ViewBuilder var keycaps: Keys

    var body: some View {
        GridRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) { keycaps }
                .fixedSize()
                .gridColumnAlignment(.trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(String(localized: title)): \(String(localized: keys))"))
        .accessibilityHint(Text(detail))
    }
}

private struct TranscriptionCard: View {
    let app: AppModel

    var body: some View {
        Card(title: "Transcription") {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").foregroundStyle(.green)
                Text("On this Mac").font(.headline)
                    .help("Audio and text never leave this Mac.")
                Spacer()
                modelBadge
            }
            if let preparation = app.preparation {
                PreparationStatus(title: app.preparationTitle(preparation), preparation: preparation, blocking: app.isBlocking(preparation))
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                if app.isMultilingual {
                    GridRow {
                        Label("Language", systemImage: "globe").foregroundStyle(.secondary)
                        Text("\(app.activeLanguage.name()) · each app keeps its own")
                    }
                }
                GridRow {
                    let variant = app.transcriptionVariant(for: app.activeLanguage)
                    Label("Model", systemImage: "cpu").foregroundStyle(.secondary)
                    Text("Whisper \(TranscriptionModelOption.option(for: variant)?.name ?? variant)")
                }
                GridRow {
                    Label("Writing", systemImage: "pencil.and.scribble").foregroundStyle(.secondary)
                    Text(writingStatus)
                }
                GridRow {
                    Label("Microphone", systemImage: "mic").foregroundStyle(.secondary)
                    Text(app.currentMicrophoneName).lineLimit(1).truncationMode(.middle)
                }
            }
            .font(.callout)
        }
    }

    private var writingStatus: LocalizedStringResource {
        let name = app.writingModelOption?.name ?? app.settings.writingModel
        switch app.writingModelState {
        case .downloading(let fraction): return "\(name), downloading \(Int(fraction * 100))%"
        case .ready: return "\(name), loaded"
        case .failed: return "\(name), download failed"
        default: return app.writingModelDownloaded ? "\(name)" : "\(name), not downloaded"
        }
    }

    @ViewBuilder
    private var modelBadge: some View {
        switch app.modelState {
        case .ready: StatusBadge(text: "Ready", color: .green)
        case .idle: StatusBadge(text: "Not loaded", color: .secondary)
        case .downloading(let fraction): StatusBadge(text: "Downloading \(Int(fraction * 100))%", color: .orange, showsProgress: true)
        case .loading(let firstTime): StatusBadge(text: firstTime || app.preparation.map(app.isBlocking) == true ? "Preparing for this Mac" : "Loading", color: .orange, showsProgress: true)
        case .failed: StatusBadge(text: "Failed", color: .red)
        }
    }
}

/// A place to dictate without leaving the app: the real flow (pill, style, language, rewrite, paste)
/// lands in this box like in any other app. It also shows what a dictation will use right now.
struct TryItCard: View {
    @Bindable var app: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool

    /// This app's own entry in the per-app style and language memory.
    private var bundleID: String? { Bundle.main.bundleIdentifier }

    var body: some View {
        Card(title: "Try it here") {
            if app.needsSetup {
                Banner(symbol: "exclamationmark.triangle.fill", message: "Finish setup so the hotkey can start dictation.", actionTitle: "Finish setup") {
                    app.openPermissions()
                }
            }
            ZStack(alignment: .topLeading) {
                // A growing multi-line field rather than a TextEditor: no scroller strip when macOS is set
                // to always show scroll bars.
                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .font(.system(.title3, design: .serif))
                    .lineSpacing(3)
                    .lineLimit(4...12)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .frame(minHeight: 96, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.background))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(focused ? Color.pencil.opacity(0.8) : Color.secondary.opacity(0.35), lineWidth: focused ? 1.5 : 0.5)
                    )
                    .accessibilityLabel(Text("Dictation test area"))
                if text.isEmpty {
                    Text(hint)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Text(verbatim: usage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if !text.isEmpty {
                    Button("Clear") { text = "" }.buttonStyle(.link)
                }
            }
        }
    }

    private var hint: LocalizedStringResource {
        let key = app.settings.gestureKey.name
        return switch (focused, app.settings.startGesture) {
        case (false, .doubleTap): "Click here, double-tap \(key), and start talking."
        case (false, .singleTap): "Click here, tap \(key), and start talking."
        case (true, .doubleTap): "Double-tap \(key) and talk. Your text lands here."
        case (true, .singleTap): "Tap \(key) and talk. Your text lands here."
        }
    }

    /// "Polished · English · Whisper Small (English)": what a dictation here will use right now.
    private var usage: String {
        let style = app.styleMemory.defaultStyle(forApp: bundleID, among: app.styles).displayName
        let language = app.languageMemory.language(forApp: bundleID)
        let variant = app.transcriptionVariant(for: language)
        let model = TranscriptionModelOption.option(for: variant)?.name ?? variant
        return [style, language.name(), "Whisper \(model)"].joined(separator: " · ")
    }
}

private struct LastDictationCard: View {
    let app: AppModel

    var body: some View {
        if let report = app.dictation.lastReport {
            Card(title: "Last dictation", trailing: trailing(for: report)) {
                if report.styleName != Style.raw.displayName {
                    Label { Text(verbatim: report.styleName) } icon: { Image(systemName: "pencil.and.scribble") }.font(.caption).foregroundStyle(Color.pencil)
                }
                Text(report.preview)
                    .font(.system(.title3, design: .serif))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if let error = app.dictation.lastError {
            Banner(symbol: "exclamationmark.triangle.fill", message: "\(error)", actionTitle: "Open settings") { app.openPermissions() }
        }
    }

    private func trailing(for report: DictationReport) -> LocalizedStringResource {
        let seconds = Double(report.stopToDelivery.components.attoseconds) / 1e18 + Double(report.stopToDelivery.components.seconds)
        let time = seconds.formatted(.number.precision(.fractionLength(2)))
        return switch report.outcome {
        case "pasted": "Pasted · \(time) s after stop"
        case "clipboardOnly": "On clipboard · \(time) s after stop"
        default: "\(report.outcome.capitalized) · \(time) s after stop"
        }
    }
}

private struct StatsColumn: View {
    let stats: UsageStats
    var columns = 1

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: columns), spacing: 12) {
            StatTile(label: "Dictations", value: stats.dictations.formatted()) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading) {
                        Text(stats.words.formatted()).font(.headline)
                        Text("words").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading) {
                        Text(Self.duration(stats.audioSeconds)).font(.headline)
                        Text("talking").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            StatTile(label: "Time saved", value: Self.duration(stats.timeSaved()), accent: true) {
                Text("vs typing at 40 wpm").font(.caption).foregroundStyle(.secondary)
            }
            StatTile(label: "Talking speed", value: stats.talkingWordsPerMinute.map(String.init) ?? "–", unit: "wpm") {
                if stats.talkingWordsPerMinute == nil {
                    Text("After a few dictations").font(.caption).foregroundStyle(.secondary)
                }
            }
            StatTile(label: "Usage", value: "\(stats.activeDaysThisMonth())", unit: stats.activeDaysThisMonth() == 1 ? "day this month" : "days this month") {
                ActivityGrid(days: stats.recentDays())
                    .padding(.top, 6)
            }
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        if minutes >= 1 { return "\(minutes)m" }
        return "\(Int(seconds))s"
    }
}
