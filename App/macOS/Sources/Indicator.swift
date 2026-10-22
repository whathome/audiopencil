import APCore
import APTranscription
import AppKit
import SwiftUI

/// What stopping a recording does: paste the text, file it as a note (audio kept), or file it as a
/// meeting note with speakers labelled.
enum Delivery: String, Equatable {
    case paste
    case note
    case meeting
}

/// Push-to-talk: where else its text goes, chosen on the pill while holding the key (it always pastes).
enum PushDestination: Equatable {
    case dailyNote
    /// A vault-relative file, e.g. "Inbox.md".
    case file(String)

    var label: String {
        switch self {
        case .dailyNote: String(localized: "Daily note")
        case .file(let path): String((path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: ""))
        }
    }
}

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
    var meetingStatus: String?
    var meetingPaused = false
    @ObservationIgnored var onOpenMeeting: (() -> Void)?
    @ObservationIgnored var onPauseMeeting: (() -> Void)?
    @ObservationIgnored var onStopMeeting: (() -> Void)?
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
    /// Chosen on the pill for this recording: always paste, or always make a note. Nil: by length.
    var deliveryOverride: Delivery?
    /// Clicked: paste → note → meeting for this recording.
    @ObservationIgnored var onToggleDelivery: (() -> Void)?
    /// Chosen in the menu.
    @ObservationIgnored var onSetDelivery: ((Delivery) -> Void)?
    /// Meeting: how many people are talking, if known (nil: worked out).
    var speakerCount: Int?
    @ObservationIgnored var onSetSpeakers: ((Int?) -> Void)?
    /// A note from this recording is linked in that day's daily note: the setting, unless changed here.
    var dailyNoteDefault = false
    /// Obsidian's Daily notes is on in the vault.
    var dailyNoteAvailable = false
    var dailyNoteOverride: Bool?
    var dailyNote: Bool { dailyNoteAvailable && (dailyNoteOverride ?? dailyNoteDefault) }
    @ObservationIgnored var onToggleDailyNote: (() -> Void)?
    /// Push-to-talk (hold the key): where else the text goes, if anywhere, and what's on offer.
    var isPushToTalk = false
    var pushDestination: PushDestination?
    var pushChoices: [PushDestination] = []
    @ObservationIgnored var onCyclePushDestination: (() -> Void)?
    @ObservationIgnored var destinationFrame: CGRect = .zero
    @ObservationIgnored var deliveryFrame: CGRect = .zero

    /// What stopping now would do.
    func delivery(at date: Date = .now) -> Delivery {
        if let deliveryOverride { return deliveryOverride }
        guard let recordingStartedAt else { return .paste }
        return date.timeIntervalSince(recordingStartedAt) >= longFormThreshold ? .note : .paste
    }
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
    /// Runs when the error on show is clicked (e.g. opening Privacy settings). Any click dismisses it.
    @ObservationIgnored private(set) var errorAction: (() -> Void)?

    func show(_ mode: Mode) {
        flashGeneration += 1
        errorAction = nil
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

    /// An error stays up until it's clicked or the next recording starts, so it can be read and acted on.
    func showError(_ message: String, action: (() -> Void)? = nil) {
        show(.error(message))
        errorAction = action
    }

    func hide() {
        flashGeneration += 1
        errorAction = nil
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
        if model.meetingStatus != nil {
            model.showStyleMenu?()
        } else if case .error = model.mode {
            let action = model.errorAction
            model.hide()
            action?()
        } else if model.mode == .picking, let id = model.pickerFrames.first(where: { $0.value.contains(point) })?.key,
           let style = model.styleChoices.first(where: { $0.id == id }) {
            model.onPick?(style)
        } else if model.mode == .listening, model.isPushToTalk, !model.pushChoices.isEmpty,
                  model.destinationFrame.insetBy(dx: -3, dy: -4).contains(point) {
            model.onCyclePushDestination?()
        } else if model.mode == .listening, !model.isPushToTalk, model.deliveryFrame.insetBy(dx: -3, dy: -4).contains(point) {
            model.onToggleDelivery?()
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
            if pointingHand {
                pointingHand = false
                NSCursor.arrow.set()
            }
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
    /// Over something clickable the pointer becomes a hand: the panel is never key, so there's no hover.
    private func gateMouse() {
        guard model.pillFrame != .zero else {
            panel.ignoresMouseEvents = true
            return
        }
        let mouse = NSEvent.mouseLocation
        panel.ignoresMouseEvents = !screenRect(model.pillFrame).insetBy(dx: -4, dy: -4).contains(mouse)
        let overControl = !panel.ignoresMouseEvents && clickableFrames.contains { screenRect($0).insetBy(dx: -3, dy: -4).contains(mouse) }
        if overControl != pointingHand {
            pointingHand = overControl
            (overControl ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
    }

    private var pointingHand = false

    /// What a click does something to in the current state (see IndicatorHostingView.mouseDown).
    private var clickableFrames: [CGRect] {
        if model.meetingStatus != nil { return [model.pillFrame] }
        return switch model.mode {
        case .listening:
            // Frames linger after their control goes, so only the ones on show now.
            ([model.isPushToTalk ? (model.pushChoices.isEmpty ? .zero : model.destinationFrame) : model.deliveryFrame, model.chipFrame]
                + (model.showsLanguage ? [model.languageFrame] : []))
                .filter { $0 != .zero }
        case .picking: Array(model.pickerFrames.values)
        case .error: [model.pillFrame] // a click dismisses it, or does what it says
        default: []
        }
    }

    /// A frame reported by the SwiftUI view (top-left origin), on screen.
    private func screenRect(_ frame: CGRect) -> NSRect {
        guard let content = panel.contentView else { return .zero }
        return panel.convertToScreen(NSRect(x: frame.minX, y: content.bounds.height - frame.maxY, width: frame.width, height: frame.height))
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
        if model.meetingStatus != nil {
            for (action, title) in [
                ("open", String(localized: "Open Meeting")),
                ("pause", model.meetingPaused ? String(localized: "Resume Meeting") : String(localized: "Pause Meeting")),
                ("stop", String(localized: "Stop Meeting"))
            ] {
                let item = NSMenuItem(title: title, action: #selector(meetingAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action
                menu.addItem(item)
            }
            openMenu = menu
            model.isMenuOpen = true
            menu.popUp(positioning: nil, at: NSPoint(x: model.pillFrame.minX, y: content.bounds.height - model.pillFrame.minY + 4), in: content)
            model.isMenuOpen = false
            openMenu = nil
            return
        }
        let header = NSMenuItem(title: String(localized: "Write it as"), action: nil, keyEquivalent: "")
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
        if model.mode == .listening, !model.isPushToTalk {
            // Paste or note, for this recording only. (Push-to-talk always pastes.)
            menu.addItem(.separator())
            let deliveryHeader = NSMenuItem(title: String(localized: "When you stop"), action: nil, keyEquivalent: "")
            deliveryHeader.isEnabled = false
            menu.addItem(deliveryHeader)
            let current = model.delivery()
            let choices: [(Delivery, String)] = [(.paste, String(localized: "Paste it")), (.note, String(localized: "Make a note")), (.meeting, String(localized: "Make a meeting note"))]
            for (delivery, title) in choices {
                let item = NSMenuItem(title: title, action: #selector(chooseDelivery(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = delivery.rawValue
                item.state = delivery == current ? .on : .off
                menu.addItem(item)
            }
            if current != .paste {
                let daily = NSMenuItem(
                    title: model.dailyNoteAvailable
                        ? String(localized: "Link in today's daily note")
                        : String(localized: "Link in today's daily note (turn on Daily notes in Obsidian)"),
                    action: #selector(toggleDailyNote(_:)), keyEquivalent: ""
                )
                daily.target = self
                daily.isEnabled = model.dailyNoteAvailable
                daily.state = model.dailyNote ? .on : .off
                menu.addItem(daily)
            }
            if current == .meeting {
                // Knowing the number helps the speaker labels.
                let speakers = NSMenuItem(title: String(localized: "Speakers"), action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                for count in [nil, 2, 3, 4, 5, 6] as [Int?] {
                    let item = NSMenuItem(title: count.map { "\($0)" } ?? String(localized: "Work it out"), action: #selector(chooseSpeakers(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = count ?? 0
                    item.state = count == model.speakerCount ? .on : .off
                    submenu.addItem(item)
                }
                speakers.submenu = submenu
                menu.addItem(speakers)
            }
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

    @objc private func chooseDelivery(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let delivery = Delivery(rawValue: raw) else { return }
        model.onSetDelivery?(delivery)
    }

    @objc private func meetingAction(_ item: NSMenuItem) {
        switch item.representedObject as? String {
        case "open": model.onOpenMeeting?()
        case "pause": model.onPauseMeeting?()
        case "stop": model.onStopMeeting?()
        default: break
        }
    }

    @objc private func toggleDailyNote(_ item: NSMenuItem) {
        model.onToggleDailyNote?()
    }

    @objc private func chooseSpeakers(_ item: NSMenuItem) {
        guard let count = item.representedObject as? Int else { return }
        model.onSetSpeakers?(count == 0 ? nil : count)
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
                    // The same mark as "Nothing heard" after stopping; a cross would read as close.
                    Image(systemName: "mic.slash.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                        .accessibilityLabel("No audio heard")
                }
                LevelBars(levels: model.levels)
                if let started = model.recordingStartedAt {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        RecordingClock(elapsed: context.date.timeIntervalSince(started), threshold: model.longFormThreshold, override: model.deliveryOverride)
                    }
                    if model.isPushToTalk {
                        // Push-to-talk always pastes: one badge says where else the text goes, if there's
                        // anywhere to choose. Clicked via IndicatorHostingView: paste → daily note → file.
                        if !model.pushChoices.isEmpty {
                            DestinationBadge(destination: model.pushDestination)
                                .background(FrameReporter { model.destinationFrame = $0 })
                        }
                    } else {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            // Clicked via IndicatorHostingView (paste → note → meeting for this recording).
                            DeliveryToggle(delivery: model.delivery(at: context.date), overridden: model.deliveryOverride != nil,
                                           dailyNote: model.dailyNote)
                                .background(FrameReporter { model.deliveryFrame = $0 })
                        }
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
                MessageText(message: message)
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                MessageText(message: message)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isMessage ? 7 : 0)
        .frame(minHeight: 34)
        // A capsule at one line; two-line messages keep the same ends.
        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(.black.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .background(FrameReporter { model.pillFrame = $0 })
    }
}

extension IndicatorView {
    private var isMessage: Bool {
        switch model.mode {
        case .notice, .error: true
        default: false
        }
    }
}

/// An error or notice: up to two lines, so a fallback explanation isn't cut off mid-sentence.
private struct MessageText: View {
    let message: String

    var body: some View {
        Text(verbatim: message)
            .font(.callout)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 440, alignment: .leading)
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
            .overlay(Capsule().stroke(controlEdge, lineWidth: 1))
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

/// Paste, note or meeting: what stopping will do, and a click moves it on for this recording. Brighter once chosen,
/// so an override is visible at a glance.
private struct DeliveryToggle: View {
    let delivery: Delivery
    let overridden: Bool
    /// A note from this recording will be linked in the daily note.
    var dailyNote = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(label)
            CycleGlyph()
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .fixedSize()
        .background(Capsule().fill(Color.white.opacity(overridden ? 0.28 : 0.12)))
        .overlay(Capsule().stroke(controlEdge, lineWidth: 1))
        .foregroundStyle(delivery == .paste ? .white : Color.accentColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibility))
        .accessibilityHint(Text("Click to switch between paste, note and meeting for this recording."))
        .accessibilityAddTraits(.isButton)
    }

    private var symbol: String {
        switch delivery {
        case .paste: "doc.on.clipboard"
        case .note: "doc.text"
        case .meeting: "person.2"
        }
    }

    /// "Note + Daily" when the note will also be linked in the daily note.
    private var label: LocalizedStringResource {
        switch (delivery, dailyNote) {
        case (.paste, _): "Paste"
        case (.note, false): "Note"
        case (.note, true): "Note + Daily"
        case (.meeting, false): "Meeting"
        case (.meeting, true): "Meeting + Daily"
        }
    }

    private var accessibility: LocalizedStringResource {
        switch (delivery, dailyNote) {
        case (.paste, _): "When you stop: paste"
        case (.note, false): "When you stop: make a note"
        case (.note, true): "When you stop: make a note and link it in today's daily note"
        case (.meeting, false): "When you stop: make a meeting note with speakers labelled"
        case (.meeting, true): "When you stop: make a meeting note with speakers labelled, linked in today's daily note"
        }
    }
}

/// Where push-to-talk's text goes: "Paste", or "Paste + Daily note" / "Paste + Inbox". Takes the place of
/// the paste/note toggle, and is only shown when there's somewhere else to choose.
private struct DestinationBadge: View {
    let destination: PushDestination?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: destination == nil ? "doc.on.clipboard" : "text.badge.plus")
            Text(verbatim: destination.map { String(localized: "Paste + \($0.label)") } ?? String(localized: "Paste"))
            CycleGlyph()
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .fixedSize()
        .background(Capsule().fill(Color.white.opacity(destination == nil ? 0.12 : 0.28)))
        .overlay(Capsule().stroke(controlEdge, lineWidth: 1))
        .foregroundStyle(destination == nil ? .white : Color.accentColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(destination.map { String(localized: "Paste, and add to \($0.label)") } ?? String(localized: "Paste only")))
        .accessibilityHint(Text("Click to also add this to the daily note or your file."))
        .accessibilityAddTraits(.isButton)
    }
}

/// Elapsed time while recording, and a countdown before a long recording switches to a note.
/// Quiet for short dictations, so the common case stays a bare meter.
private struct RecordingClock: View {
    let elapsed: TimeInterval
    let threshold: TimeInterval
    /// Chosen on the pill: the clock stops counting down to a note that won't happen (or already will).
    var override: Delivery?

    /// Short dictations show no clock at all.
    static let showAfter: TimeInterval = 30
    /// Warn this long before a recording turns into a note.
    static let warnBefore: TimeInterval = 30

    var body: some View {
        Group {
            // The paste/note toggle next to it says which; the clock only counts down to an automatic switch.
            if override == nil, elapsed < threshold, elapsed >= threshold - Self.warnBefore {
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

/// Ends a pill control that a click moves on to its next choice, so it doesn't read as a status label
/// (the style chip's chevron does the same for its menu).
private struct CycleGlyph: View {
    var body: some View {
        Image(systemName: "arrow.2.squarepath")
            .font(.system(size: 8, weight: .bold))
            .opacity(0.75)
            .padding(.leading, 1)
            .accessibilityHidden(true)
    }
}

/// A clickable capsule's edge, as on a button: the pill's own 1 pt outline, a little brighter.
private let controlEdge = Color.white.opacity(0.2)

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
