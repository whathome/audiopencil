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
                    Banner(symbol: "exclamationmark.triangle.fill", message: "Finish setup so the Fn key can start dictation.", actionTitle: "Finish setup") {
                        app.page = .setup
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        HotkeyCard(app: app)
                        TranscriptionCard(app: app)
                        LastDictationCard(app: app)
                    }
                    .frame(maxWidth: .infinity)

                    StatsColumn(stats: app.stats)
                        .frame(width: 210)
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 30, weight: .bold, design: .serif))
            Text(subtitle).font(.title3).foregroundStyle(.secondary)
        }
    }
}

private struct HotkeyCard: View {
    let app: AppModel

    var body: some View {
        Card(title: "Hotkey") {
            HStack(spacing: 8) {
                Chip(label: "Fn", symbol: "globe", isOn: true)
                Chip(label: "⌃⌥ Space", isOn: app.settings.fallbackShortcutEnabled)
                Spacer()
                Button("Change…") { app.page = .settings }
                    .buttonStyle(.link)
            }
            Divider().padding(.vertical, 2)
            HStack(alignment: .top, spacing: 12) {
                if app.settings.holdFnForRaw {
                    Gesture(title: "Push to talk", detail: "Hold, release to paste") {
                        KeyCap(label: "hold fn")
                    }
                }
                Gesture(title: "In a style", detail: "Double-tap; 1–9 to switch") {
                    KeyCap(label: "fn"); KeyCap(label: "fn")
                }
                Gesture(title: "Stop and paste", detail: stopDetail) {
                    KeyCap(label: "fn")
                    if app.settings.stopGesture == .doubleTapFn { KeyCap(label: "fn") }
                    if app.settings.returnStops { KeyCap(label: "return", symbol: "return") }
                }
                Gesture(title: "Cancel", detail: "Nothing is pasted") {
                    KeyCap(label: "esc")
                }
            }
        }
    }

    private var stopDetail: String {
        let fn = app.settings.stopGesture == .singleTapFn ? "Tap" : "Double-tap"
        return app.settings.returnStops ? "\(fn) or Return" : fn
    }
}

private struct Gesture<Keys: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var keys: Keys

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) { keys }
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Label("Model", systemImage: "cpu").foregroundStyle(.secondary)
                    Text("Whisper \(TranscriptionModelOption.option(for: app.settings.transcriptionModel)?.name ?? app.settings.transcriptionModel)")
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

    private var writingStatus: String {
        let name = app.writingModelOption?.name ?? app.settings.writingModel
        switch app.writingModelState {
        case .downloading(let fraction): return "\(name), downloading \(Int(fraction * 100))%"
        case .ready: return "\(name), loaded"
        case .failed: return "\(name), download failed"
        default: return app.writingModelDownloaded ? name : "\(name), not downloaded"
        }
    }

    @ViewBuilder
    private var modelBadge: some View {
        switch app.modelState {
        case .ready: StatusBadge(text: "Ready", color: .green)
        case .idle: StatusBadge(text: "Not loaded", color: .secondary)
        case .downloading(let fraction): StatusBadge(text: "Downloading \(Int(fraction * 100))%", color: .orange, showsProgress: true)
        case .loading(let firstTime): StatusBadge(text: firstTime ? "Preparing (first time)" : "Loading", color: .orange, showsProgress: true)
        case .failed: StatusBadge(text: "Failed", color: .red)
        }
    }
}

private struct LastDictationCard: View {
    let app: AppModel

    var body: some View {
        if let report = app.dictation.lastReport {
            Card(title: "Last dictation", trailing: trailing(for: report)) {
                if report.styleName != Style.raw.name {
                    Label(report.styleName, systemImage: "pencil.and.scribble").font(.caption).foregroundStyle(Color.pencil)
                }
                Text(report.preview)
                    .font(.system(.title3, design: .serif))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Card(title: "Last dictation") {
                HStack(spacing: 10) {
                    Image(systemName: "text.cursor").font(.title2).foregroundStyle(Color.pencil)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Try your first dictation").font(.headline)
                        Text("Click into any text field, double-tap Fn, and start talking.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
        if let error = app.dictation.lastError {
            Banner(symbol: "exclamationmark.triangle.fill", message: error, actionTitle: "Open setup") { app.page = .setup }
        }
    }

    private func trailing(for report: DictationReport) -> String {
        let outcome = switch report.outcome {
        case "pasted": "Pasted"
        case "clipboardOnly": "On clipboard"
        default: report.outcome.capitalized
        }
        let seconds = Double(report.stopToDelivery.components.attoseconds) / 1e18 + Double(report.stopToDelivery.components.seconds)
        return "\(outcome) · \(String(format: "%.2f", seconds)) s after stop"
    }
}

private struct StatsColumn: View {
    let stats: UsageStats

    var body: some View {
        VStack(spacing: 12) {
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
            StatTile(label: "Usage", value: "\(stats.activeDaysThisMonth())", unit: "days this month") {
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

/// Placeholder for sections arriving in later milestones.
struct ComingSoonPage: View {
    let title: String
    let symbol: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: title, subtitle: message)
            Card {
                HStack(spacing: 12) {
                    Image(systemName: symbol).font(.largeTitle).foregroundStyle(Color.pencil)
                    Text("Coming in a later milestone.").foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 980, alignment: .leading)
    }
}
