import APCore
import APTranscription
import AppKit
import SwiftUI

/// State shown by the floating indicator at the bottom centre of the screen.
@Observable
final class IndicatorModel {
    enum Mode: Equatable {
        case hidden
        case listening
        /// Waiting for Whisper. `firstTime`: compiling for this Mac, which can take minutes (once per model).
        case preparingModel(firstTime: Bool)
        case processing
        /// Style picker after stop.
        case picking
        /// Writing model is producing the styled text.
        case rewriting(String)
        case clipboard
        case nothingHeard
        case notice(String)
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
    /// A first-time model preparation in progress: shown while waiting, and as a heads-up while recording.
    var preparation: ModelPreparation?
    /// A one-off note shown above the pill while recording, e.g. that a language is on its starter model.
    var note: String?
    /// Language of the current recording, shown as a badge when more than one is in use.
    var currentLanguage: SpokenLanguage?
    /// Languages offered in the menu; one or none hides the badge and the menu section.
    var languageChoices: [SpokenLanguage] = []
    @ObservationIgnored var onSelectLanguage: ((SpokenLanguage) -> Void)?
    var showsLanguage: Bool { languageChoices.count > 1 || currentLanguage?.isEnglish == false }
    /// Clicked in the post-stop picker.
    @ObservationIgnored var onPick: ((Style) -> Void)?
    /// Set by the panel: show the style menu at the chip.
    @ObservationIgnored var showStyleMenu: (() -> Void)?
    /// The style menu is open: keys belong to it, not to dictation.
    var isMenuOpen = false
    /// Frames in the panel's content view (SwiftUI global, top-left origin), for AppKit click handling.
    @ObservationIgnored var pillFrame: CGRect = .zero
    @ObservationIgnored var chipFrame: CGRect = .zero
    @ObservationIgnored var languageFrame: CGRect = .zero
    @ObservationIgnored var pickerFrames: [String: CGRect] = [:]
    /// When the current recording started, for the elapsed clock; nil when not recording.
    var recordingStartedAt: Date?
    /// Recordings this long become notes instead of pasting; the pill warns as it approaches.
    var longFormThreshold: Double = 300
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
        } else {
            recordingStartedAt = nil
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
        recordingStartedAt = nil
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
        } else if model.mode == .listening,
                  model.chipFrame.insetBy(dx: -4, dy: -4).contains(point) || model.languageFrame.insetBy(dx: -4, dy: -4).contains(point) {
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
        let header = NSMenuItem(title: String(localized: "Deliver this dictation as"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for style in model.styleChoices {
            let item = NSMenuItem(
                title: style.displayName,
                action: #selector(choose(_:)),
                keyEquivalent: style.shortcut.map(String.init) ?? ""
            )
            item.keyEquivalentModifierMask = []
            item.target = self
            item.representedObject = style.id
            item.state = style.id == model.currentStyle?.id ? .on : .off
            menu.addItem(item)
        }
        if model.mode == .listening, model.showsLanguage {
            // One language per recording: switching transcribes what you've said again in the new one.
            menu.addItem(.separator())
            let languageHeader = NSMenuItem(title: String(localized: "Language"), action: nil, keyEquivalent: "")
            languageHeader.isEnabled = false
            menu.addItem(languageHeader)
            for language in model.languageChoices {
                let item = NSMenuItem(title: language.name(), action: #selector(chooseLanguage(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = language.code
                item.state = language == model.currentLanguage ? .on : .off
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let tip = NSMenuItem(title: String(localized: "Tip: press the number while you talk"), action: nil, keyEquivalent: "")
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

    @objc private func chooseLanguage(_ item: NSMenuItem) {
        guard let code = item.representedObject as? String else { return }
        model.onSelectLanguage?(SpokenLanguage(code: code))
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
            if model.mode == .listening, let preparation = model.preparation {
                // Said at the start, not after you've talked for minutes.
                TimelineView(.periodic(from: preparation.startedAt, by: 1)) { context in
                    let left = max(0, preparation.estimatedSeconds - context.date.timeIntervalSince(preparation.startedAt))
                    Text(left >= 120
                         ? "The speech model is being prepared for this Mac, about \(Int((left / 60).rounded())) min left. Keep talking; your text arrives when it's ready."
                         : left > 15
                         ? "The speech model is being prepared for this Mac, about \(Int((left / 10).rounded()) * 10) s left. Keep talking; your text arrives when it's ready."
                         : "The speech model is almost ready. Keep talking; your text arrives when it's ready.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: 460)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.82)))
                }
            }
            if model.mode == .listening, model.preparation == nil, let note = model.note {
                Text(verbatim: note)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 460)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.82)))
            }
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
                        .accessibilityLabel("No audio heard")
                }
                LevelBars(levels: model.levels)
                if let started = model.recordingStartedAt {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        RecordingClock(elapsed: context.date.timeIntervalSince(started), threshold: model.longFormThreshold)
                    }
                }
                if model.showsLanguage, let language = model.currentLanguage {
                    // Clicked via IndicatorHostingView (opens the menu at its Language section).
                    LanguageBadge(language: language)
                        .background(FrameReporter { model.languageFrame = $0 })
                }
                if let style = model.currentStyle {
                    // Clicked via IndicatorHostingView (opens the style menu).
                    StyleChip(style: style)
                        .background(FrameReporter { model.chipFrame = $0 })
                }
            case .picking:
                if let picker = model.picker {
                    PickerRow(picker: picker) { id, frame in model.pickerFrames[id] = frame }
                }
            case .rewriting(let name):
                Image(systemName: "pencil.and.scribble")
                Text(verbatim: name).font(.callout.weight(.medium))
                ProgressView(value: model.rewriteProgress)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .frame(width: 90)
            case .preparingModel(let firstTime):
                ProgressView().controlSize(.small).tint(.white)
                if let preparation = model.preparation {
                    TimelineView(.periodic(from: preparation.startedAt, by: 1)) { context in
                        Text("Preparing for this Mac · step \(preparation.step) of \(preparation.steps) · \(PreparationStatus.progressText(elapsed: context.date.timeIntervalSince(preparation.startedAt), estimate: preparation.estimatedSeconds))")
                            .font(.callout.monospacedDigit())
                    }
                } else {
                    Text(firstTime ? "Preparing the model for this Mac (first time only)…" as LocalizedStringResource : "Preparing model…").font(.callout)
                }
            case .processing:
                ProgressView().controlSize(.small).tint(.white)
            case .clipboard:
                Image(systemName: "doc.on.clipboard")
                Text("On clipboard: press ⌘V").font(.callout)
            case .nothingHeard:
                Image(systemName: "mic.slash")
                Text("Nothing heard").font(.callout)
            case .notice(let message):
                Image(systemName: "doc.badge.clock")
                Text(verbatim: message).font(.callout).lineLimit(1)
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(verbatim: message).font(.callout).lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(.black.opacity(0.82)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .background(FrameReporter { model.pillFrame = $0 })
    }
}

/// The recording's language, e.g. "FR". Only shown when more than one language is in use.
private struct LanguageBadge: View {
    let language: SpokenLanguage

    var body: some View {
        Text(language.badge)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.18)))
            .accessibilityLabel("Language: \(language.name())")
            .accessibilityHint("Click to choose another language.")
            .accessibilityAddTraits(.isButton)
    }
}

/// The current style, with its number key so the switch-while-talking shortcut is learnable at a glance.
private struct StyleChip: View {
    let style: Style

    var body: some View {
        HStack(spacing: 4) {
            if let shortcut = style.shortcut {
                Text("\(shortcut)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .frame(width: 14, height: 14)
                    .background(RoundedRectangle(cornerRadius: 3).fill(badgeFill))
            }
            Text(name)
            Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold))
        }
        .font(.caption.weight(.semibold))
        .padding(.leading, style.shortcut == nil ? 8 : 4)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(fill))
        .foregroundStyle(style.isRaw ? Color.white : Color.black.opacity(0.8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Style: \(name)"))
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
    }

    private var name: String { style.shortDisplayName }
    private var fill: Color { style.isRaw ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.9) }
    private var badgeFill: Color { style.isRaw ? Color.white.opacity(0.18) : Color.black.opacity(0.14) }
    private var hint: String {
        if let shortcut = style.shortcut { return String(localized: "Number key \(shortcut). Click to choose another style.") }
        return String(localized: "Click to choose another style.")
    }
}

/// Elapsed time while recording, and what stopping will do once the recording is long enough
/// to become a note. Quiet for short dictations, so the common case stays a bare meter.
private struct RecordingClock: View {
    let elapsed: TimeInterval
    let threshold: TimeInterval

    /// Short dictations show no clock at all.
    static let showAfter: TimeInterval = 30
    /// Warn this long before a recording turns into a note.
    static let warnBefore: TimeInterval = 30

    var body: some View {
        Group {
            if elapsed >= threshold {
                HStack(spacing: 3) {
                    Image(systemName: "doc.text")
                    Text("Note · \(Self.clock(elapsed))")
                }
                .foregroundStyle(Color.accentColor)
            } else if elapsed >= threshold - Self.warnBefore {
                Text("Note in \(Self.clock(threshold - elapsed))")
                    .foregroundStyle(Color.accentColor)
            } else if elapsed >= Self.showAfter {
                Text(Self.clock(elapsed))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .font(.caption.monospacedDigit().weight(.medium))
        .fixedSize()
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

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

/// Style choices after stop: number badges, the default highlighted, a shrinking countdown underline.
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
                    Text(verbatim: style.shortDisplayName).font(.callout)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Listening")
        .accessibilityValue("Level \(Int((levels.last ?? 0) * 100)) percent")
    }
}
