import APCore
import AppKit
import SwiftUI

/// State shown by the floating indicator at the bottom centre of the screen.
@Observable
final class IndicatorModel {
    enum Mode: Equatable {
        case hidden
        case listening
        case preparingModel
        case processing
        /// Style picker after stop.
        case picking
        /// Writing model is producing the styled text.
        case rewriting(String)
        case clipboard
        case nothingHeard
        case error(String)
    }

    static let barCount = 14

    private(set) var mode: Mode = .hidden
    private(set) var levels = [Float](repeating: 0, count: barCount)
    private(set) var noAudio = false
    var liveText = ""
    var showLiveText = false
    /// Style shown next to the level bars while recording; nil for raw.
    var styleName: String?
    /// 0…1 while rewriting.
    var rewriteProgress: Double = 0
    var picker: PickerState?

    struct PickerState: Equatable {
        var styles: [Style]
        var selected: Style
        var autoConfirm: Double
        var shownAt = Date()
    }

    private var quietSince: Date?
    private var flashGeneration = 0

    func show(_ mode: Mode) {
        flashGeneration += 1
        if mode == .listening {
            levels = .init(repeating: 0, count: Self.barCount)
            noAudio = false
            quietSince = nil
            liveText = ""
        }
        self.mode = mode
    }

    /// Shows a transient state, then hides.
    func flash(_ mode: Mode, seconds: Double = 1.4) {
        show(mode)
        let generation = flashGeneration
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if generation == flashGeneration { self.mode = .hidden }
        }
    }

    func hide() {
        flashGeneration += 1
        mode = .hidden
    }

    /// Adds a 0…1 level. After ~1.5 s near silence the "no audio" cross appears.
    func push(_ level: Float) {
        guard mode == .listening else { return }
        levels.removeFirst()
        levels.append(level)
        if level < 0.1 {
            let since = quietSince ?? Date()
            quietSince = since
            noAudio = Date().timeIntervalSince(since) > 1.5
        } else {
            quietSince = nil
            noAudio = false
        }
    }
}

/// Borderless, non-activating panel: never takes focus from the app being dictated into.
final class IndicatorPanelController {
    private let model: IndicatorModel
    private let panel: NSPanel
    private static let size = NSSize(width: 460, height: 140)

    init(model: IndicatorModel) {
        self.model = model
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: IndicatorView(model: model))
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = model.mode
        } onChange: {
            Task { @MainActor in
                self.update()
                self.observe()
            }
        }
    }

    private func update() {
        if model.mode == .hidden {
            panel.orderOut(nil)
            return
        }
        if !panel.isVisible, let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 20))
        }
        panel.orderFrontRegardless()
    }
}

struct IndicatorView: View {
    let model: IndicatorModel

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            if model.showLiveText, model.mode == .listening, !model.liveText.isEmpty {
                Text(model.liveText)
                    .font(.callout)
                    .lineLimit(3)
                    .truncationMode(.head)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.75)))
            }
            pill
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeOut(duration: 0.12), value: model.mode)
    }

    private var pill: some View {
        HStack(spacing: 8) {
            switch model.mode {
            case .hidden:
                EmptyView()
            case .listening:
                if model.noAudio {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.red)
                }
                LevelBars(levels: model.levels)
                if let styleName = model.styleName {
                    Text(styleName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.85)))
                        .foregroundStyle(.black.opacity(0.8))
                }
            case .picking:
                if let picker = model.picker { PickerRow(picker: picker) }
            case .rewriting(let name):
                Image(systemName: "pencil.and.scribble")
                Text(name).font(.callout.weight(.medium))
                ProgressView(value: model.rewriteProgress)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .frame(width: 90)
            case .preparingModel:
                ProgressView().controlSize(.small).tint(.white)
                Text("Preparing model…").font(.callout)
            case .processing:
                ProgressView().controlSize(.small).tint(.white)
            case .clipboard:
                Image(systemName: "doc.on.clipboard")
                Text("On clipboard").font(.callout)
            case .nothingHeard:
                Image(systemName: "mic.slash")
                Text("Nothing heard").font(.callout)
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(message).font(.callout).lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(.black.opacity(0.82)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }
}

/// Style choices after stop: number badges, the default highlighted, a shrinking countdown underline.
private struct PickerRow: View {
    let picker: IndicatorModel.PickerState

    var body: some View {
        HStack(spacing: 6) {
            ForEach(picker.styles) { style in
                let isSelected = style.id == picker.selected.id
                HStack(spacing: 4) {
                    Text("\(style.shortcut ?? 0)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .frame(width: 15, height: 15)
                        .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.18)))
                    Text(style.isRaw ? "Raw" : style.name).font(.callout)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(isSelected ? Color.accentColor.opacity(0.85) : .clear))
                .foregroundStyle(isSelected ? .black.opacity(0.85) : .white)
                .overlay(alignment: .bottom) {
                    if isSelected {
                        TimelineView(.animation) { context in
                            let elapsed = context.date.timeIntervalSince(picker.shownAt)
                            let remaining = max(0, 1 - elapsed / max(picker.autoConfirm, 0.1))
                            Capsule().fill(.white.opacity(0.9)).frame(height: 2).scaleEffect(x: remaining, anchor: .leading)
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
        }
    }
}

private struct LevelBars: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 3, height: 4 + CGFloat(levels[index]) * 18)
            }
        }
        .frame(height: 22)
        .animation(.linear(duration: 0.08), value: levels)
    }
}
