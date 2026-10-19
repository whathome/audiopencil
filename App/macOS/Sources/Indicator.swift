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
    /// Style of the current recording, shown as a clickable chip; nil when not recording.
    var currentStyle: Style?
    /// Styles offered in the chip's menu and the post-stop picker, in number order.
    var styleChoices: [Style] = []
    /// Chosen from the chip's menu while recording.
    @ObservationIgnored var onSelectStyle: ((Style) -> Void)?
    /// Clicked in the post-stop picker.
    @ObservationIgnored var onPick: ((Style) -> Void)?
    /// Set by the panel: show the style menu at the chip.
    @ObservationIgnored var showStyleMenu: (() -> Void)?
    /// The style menu is open: keys belong to it, not to dictation.
    var isMenuOpen = false
    /// Frames in the panel's content view (SwiftUI global, top-left origin), for AppKit click handling.
    @ObservationIgnored var pillFrame: CGRect = .zero
    @ObservationIgnored var chipFrame: CGRect = .zero
    @ObservationIgnored var pickerFrames: [String: CGRect] = [:]
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
/// Handles clicks in AppKit: the panel is never key, and SwiftUI buttons don't fire in a
/// non-key, non-activating window. Click targets come from frames the SwiftUI view reports.
private final class IndicatorHostingView: NSHostingView<IndicatorView> {
    var model: IndicatorModel?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let model else { return super.mouseDown(with: event) }
        let local = convert(event.locationInWindow, from: nil)
        let point = isFlipped ? local : CGPoint(x: local.x, y: bounds.height - local.y)
        if model.mode == .picking, let id = model.pickerFrames.first(where: { $0.value.contains(point) })?.key,
           let style = model.styleChoices.first(where: { $0.id == id }) {
            model.onPick?(style)
        } else if model.mode == .listening, model.chipFrame.insetBy(dx: -4, dy: -4).contains(point) {
            model.showStyleMenu?()
        } else {
            super.mouseDown(with: event)
        }
    }
}

final class IndicatorPanelController: NSObject {
    private let model: IndicatorModel
    private let panel: NSPanel
    private static let size = NSSize(width: 640, height: 140)
    private var mouseGate: Timer?
    private weak var openMenu: NSMenu?

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
        // Clicks are accepted only while the pointer is over the pill (see gateMouse); the rest of
        // the panel stays click-through. Non-activating, and never key: the app being dictated
        // into keeps focus, so the paste still lands there.
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let hosting = IndicatorHostingView(rootView: IndicatorView(model: model))
        hosting.model = model
        panel.contentView = hosting
        super.init()
        model.showStyleMenu = { [weak self] in self?.presentStyleMenu() }
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
        if model.mode != .listening, model.mode != .picking {
            openMenu?.cancelTracking() // recording ended under an open menu
        }
        if model.mode == .hidden {
            panel.orderOut(nil)
            mouseGate?.invalidate()
            mouseGate = nil
            panel.ignoresMouseEvents = true
            return
        }
        if mouseGate == nil {
            mouseGate = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.gateMouse() }
            }
        }
        if !panel.isVisible, let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 20))
        }
        panel.orderFrontRegardless()
    }

    /// Accept mouse events only over the pill, so the transparent rest of the panel never blocks clicks.
    private func gateMouse() {
        guard let content = panel.contentView, model.pillFrame != .zero else {
            panel.ignoresMouseEvents = true
            return
        }
        let pill = model.pillFrame
        let local = NSRect(x: pill.minX, y: content.bounds.height - pill.maxY, width: pill.width, height: pill.height)
        let onScreen = panel.convertToScreen(local).insetBy(dx: -4, dy: -4)
        panel.ignoresMouseEvents = !onScreen.contains(NSEvent.mouseLocation)
    }

    #if DEBUG
    /// Screen point (Core Graphics, top-left origin) of the style chip, or just above the pill.
    func debugPoint(chip: Bool, pickerStyleID: String? = nil) -> CGPoint? {
        guard let content = panel.contentView, model.pillFrame != .zero else { return nil }
        let pill = model.pillFrame
        var target = chip && model.chipFrame != .zero ? model.chipFrame : pill
        if let id = pickerStyleID, let frame = model.pickerFrames[id] { target = frame }
        let above = !chip && pickerStyleID == nil
        let local = NSPoint(x: target.midX, y: content.bounds.height - target.midY + (above ? 40 : 0))
        let screen = panel.convertPoint(toScreen: local)
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: screen.x, y: height - screen.y)
    }

    var debugIgnoresMouse: Bool { panel.ignoresMouseEvents }
    #endif

    /// Native menu of styles with their number keys, so the shortcuts are learnable.
    private func presentStyleMenu() {
        guard let content = panel.contentView, openMenu == nil else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "Deliver this dictation as", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for style in model.styleChoices {
            let item = NSMenuItem(
                title: style.isRaw ? "Raw transcript" : style.name,
                action: #selector(choose(_:)),
                keyEquivalent: style.shortcut.map(String.init) ?? ""
            )
            item.keyEquivalentModifierMask = []
            item.target = self
            item.representedObject = style.id
            item.state = style.id == model.currentStyle?.id ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let tip = NSMenuItem(title: "Tip: press the number while you talk", action: nil, keyEquivalent: "")
        tip.isEnabled = false
        menu.addItem(tip)

        let pill = model.pillFrame
        let anchor = NSPoint(x: pill.maxX - 60, y: content.bounds.height - pill.minY + 4)
        openMenu = menu
        model.isMenuOpen = true
        let current = menu.items.first { $0.state == .on }
        menu.popUp(positioning: current, at: anchor, in: content) // runs until the menu closes
        model.isMenuOpen = false
        openMenu = nil
    }

    @objc private func choose(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, let style = model.styleChoices.first(where: { $0.id == id }) else { return }
        if model.mode == .picking {
            model.onPick?(style)
        } else {
            model.onSelectStyle?(style)
        }
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
                if let style = model.currentStyle {
                    // Clicked via IndicatorHostingView (opens the style menu).
                    HStack(spacing: 3) {
                        Text(style.isRaw ? "Raw" : style.name)
                        Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold))
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(style.isRaw ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.9)))
                    .foregroundStyle(style.isRaw ? Color.white : Color.black.opacity(0.8))
                    .background(FrameReporter { model.chipFrame = $0 })
                }
            case .picking:
                if let picker = model.picker {
                    PickerRow(picker: picker) { id, frame in model.pickerFrames[id] = frame }
                }
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
        .background(FrameReporter { model.pillFrame = $0 })
    }
}

/// Style choices after stop: number badges, the default highlighted, a shrinking countdown underline.
/// Reports a view's frame in the hosting view's coordinates.
private struct FrameReporter: View {
    let report: (CGRect) -> Void

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { report(geometry.frame(in: .global)) }
                .onChange(of: geometry.frame(in: .global)) { _, frame in report(frame) }
        }
    }
}

private struct PickerRow: View {
    let picker: IndicatorModel.PickerState
    /// Each choice's frame, so a click can pick it.
    let reportFrame: (String, CGRect) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(picker.styles) { style in
                choice(style, isSelected: style.id == picker.selected.id)
                    .background(FrameReporter { reportFrame(style.id, $0) })
            }
        }
    }

    private func choice(_ style: Style, isSelected: Bool) -> some View {
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
