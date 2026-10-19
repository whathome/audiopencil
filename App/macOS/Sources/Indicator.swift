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
