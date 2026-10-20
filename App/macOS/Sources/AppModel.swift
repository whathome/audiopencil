import APAudio
import APCore
import APModels
import APStorage
import APSummary
import APSync
import APTranscription
import AppKit
import ServiceManagement

enum TranscriptionModelState: Equatable {
    case idle
    case downloading(Double)
    case loading(firstTime: Bool)
    case ready
    case failed(String)
}

/// App-wide state and wiring: settings, permissions, the Whisper model, hotkeys and the dictation loop.
@Observable
final class AppModel {
    private static let settingsKey = "dictationSettings"
    private static let statsKey = "usageStats"
    static let stylesKey = "styles"
    static let styleMemoryKey = "styleMemory"

    /// Page shown in the main window.
    var page: Page = .dictation
    /// Counts only, for the stats column.
    private(set) var stats: UsageStats = AppModel.loadStats()

    /// Something the hotkey needs is missing.
    var needsSetup: Bool {
        !permissions.allRequiredGranted || !hotkeyActive || !permissions.fnKeyIsFree
    }

    var settings: DictationSettings {
        didSet { settingsChanged(from: oldValue) }
    }

    let permissions = Permissions()
    let indicator = IndicatorModel()
    let vault = VaultController()
    @ObservationIgnored private(set) var sync: SyncController!
    @ObservationIgnored private(set) var notes: NoteMaker!
    @ObservationIgnored private(set) var advisor: ModelAdvisor!
    /// The user's writing for "Like me". Shared through the vault settings file.
    var writingSamples: [WritingSample] = AppModel.loadWritingSamples() {
        didSet { writingSamplesChanged(from: oldValue) }
    }
    /// Vault-wide: remove "regular" audio a year after recording. Shared through the settings file.
    var expireRegularAudio: Bool = UserDefaults.standard.object(forKey: "expireRegularAudio") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(expireRegularAudio, forKey: "expireRegularAudio")
            if !applyingSync, expireRegularAudio != oldValue { sync?.syncSoon() }
        }
    }
    /// Master tag list from the vault settings file. Approving new tags in a review adds them here.
    var tags: [String] = [] {
        didSet { if !applyingSync, tags != oldValue { sync?.syncSoon() } }
    }
    /// Set while applying a synced config, so the change doesn't schedule another sync.
    @ObservationIgnored var applyingSync = false
    /// Debug builds: a short long-form threshold for testing (not saved or synced).
    @ObservationIgnored var debugLongFormThreshold: Double?
    var modelState: TranscriptionModelState = .idle
    private(set) var hotkeyActive = false
    /// Recent Fn events and gesture decisions, newest last.
    private(set) var hotkeyTrace: [String] = []
    @ObservationIgnored private var traceOrigin: TimeInterval?
    private(set) var memoryPressure: MemoryPressureMonitor.Level = .normal
    private(set) var whisper: WhisperEngine
    /// MLX writing model for styles. Never resident at the same time as Whisper.
    var writing: SummaryEngine
    var writingModelState: TranscriptionModelState = .idle
    /// Styles in picker order. Local until milestone 4 moves them into the vault config.
    var styles: [Style] {
        didSet { saveStyles() }
    }
    var styleMemory: StyleMemory {
        didSet { saveStyleMemory() }
    }
    /// Connected input devices, kept current as devices come and go.
    private(set) var microphones: [Microphone] = MicrophoneCatalog.current()
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var launchAtLoginNeedsApproval = SMAppService.mainApp.status == .requiresApproval

    /// The microphone the next recording will use: first connected preference, else nil (system default).
    var currentMicrophone: Microphone? {
        MicrophoneCatalog.resolve(preferred: settings.preferredMicrophones.map(\.uid), among: microphones)
    }

    /// Device name only, for tight spaces.
    var microphoneShortName: String {
        currentMicrophone?.name ?? MicrophoneCatalog.systemDefault(among: microphones)?.name ?? "System default"
    }

    var currentMicrophoneName: String {
        if let currentMicrophone { return currentMicrophone.name }
        let fallback = MicrophoneCatalog.systemDefault(among: microphones)?.name ?? "unknown"
        return "System default (\(fallback))"
    }

    @ObservationIgnored let coordinator = ModelCoordinator()
    @ObservationIgnored private(set) var dictation: DictationController!
    @ObservationIgnored private let hotkeys = HotkeyMonitor()
    @ObservationIgnored private var detector: FnTapDetector
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    /// A press-and-hold recording is running; releasing Fn stops it.
    @ObservationIgnored private var holdRecording = false
    /// Longer than the longest tap (0.30 s), short enough to feel immediate.
    static let holdThreshold: TimeInterval = 0.35
    #if DEBUG
    /// Simulated key presses from the debug hook make dictations dry runs until this time.
    @ObservationIgnored private var debugDryRunUntil = Date.distantPast
    @ObservationIgnored private var debugSavedCursor: CGPoint?
    #endif
    @ObservationIgnored private var indicatorPanel: IndicatorPanelController?
    @ObservationIgnored private var modelTask: Task<Void, any Error>?
    @ObservationIgnored private var memoryMonitor: MemoryPressureMonitor?
    @ObservationIgnored private var permissionPoll: Task<Void, Never>?
    @ObservationIgnored private var debugObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var microphoneCatalog: MicrophoneCatalog?
    @ObservationIgnored var writingTask: Task<Void, Never>?

    init() {
        let settings = Self.loadSettings()
        self.settings = settings
        self.whisper = WhisperEngine(variant: settings.transcriptionModel)
        self.writing = SummaryEngine(modelID: settings.writingModel)
        self.styles = Self.loadStyles()
        self.styleMemory = Self.loadStyleMemory()
        self.detector = FnTapDetector(configuration: .init(maxGapBetweenTaps: settings.doubleTapWindow))
        self.dictation = DictationController(
            indicator: indicator,
            engine: { [unowned self] in whisper },
            waitForModel: { [unowned self] in try await waitForModel() },
            rewrite: { [unowned self] transcript, style, progress in
                try await rewrite(transcript, style: style, progress: progress)
            }
        )
        indicator.showLiveText = settings.showLiveText
        dictation.onStyleUsed = { [unowned self] style, app in styleMemory.remember(style.id, forApp: app) }
        sync = SyncController(vault: vault)
        sync.localConfig = { [unowned self] base in localConfig(from: base) }
        sync.apply = { [unowned self] config in apply(config) }
        sync.retentionFolders = { [unowned self] in
            Array(Set(styles.map { notes.folder(for: $0) } + [NoteMaker.defaultFolder, StarterKit.samplesFolder]))
        }
        sync.expireRegularAudio = { [unowned self] in expireRegularAudio }
        vault.onLocationReady = { [unowned self] in sync.syncSoon(after: .zero) }
        notes = NoteMaker(app: self)
        advisor = ModelAdvisor(app: self)
        dictation.onLongForm = { [unowned self] capture in notes.makeLongFormNote(capture) }
        dictation.onQuickNote = { [unowned self] capture in notes.saveQuick(capture) }
        applyNoteSettings()
        dictation.onPrepareRewrite = { [unowned self] _ in prefetchWritingModel() }
        applyPickerSettings()
        dictation.onDelivered = { [unowned self] words, audioSeconds in
            stats.record(words: words, audioSeconds: audioSeconds)
            if let data = try? JSONEncoder().encode(stats) {
                UserDefaults.standard.set(data, forKey: Self.statsKey)
            }
        }
    }

    private static func loadStats() -> UsageStats {
        guard let data = UserDefaults.standard.data(forKey: statsKey),
              let stats = try? JSONDecoder().decode(UsageStats.self, from: data)
        else { return UsageStats() }
        return stats
    }

    // MARK: Lifecycle

    func bootstrap() {
        indicatorPanel = IndicatorPanelController(model: indicator)
        hotkeys.handler = { [unowned self] event, time in handle(event, at: time) }
        hotkeys.onDiagnostic = { [unowned self] text in trace(text) }
        memoryMonitor = MemoryPressureMonitor { level in
            Task { @MainActor [weak self] in self?.memoryPressure = level }
        }
        microphoneCatalog = MicrophoneCatalog { microphones in
            Task { @MainActor [weak self] in self?.microphones = microphones }
        }
        applyAppPresence()
        sync.start()
        permissions.refresh()
        startHotkeysIfPossible()
        if needsSetup { page = .setup }
        prepareModel()
        pollPermissions()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(30)) // after startup settles
            self?.advisor.checkIfDue()
        }
        #if DEBUG
        listenForDebugCommands()
        #endif
    }

    #if DEBUG
    /// Lets scripts/debug-dictation.sh drive dictation without key presses, for end-to-end timing.
    /// Debug builds only; dictations started this way never paste.
    private func listenForDebugCommands() {
        debugObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.weshopkins.audiopencil.debug"), object: nil, queue: .main
        ) { [unowned self] note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated {
                Log.dictation.notice("Debug command: \(command, privacy: .public)")
                switch command {
                case "start": startDictation(dryRun: true)
                case "warm": dictation.warmUp(deviceID: currentMicrophone?.deviceID) // a lone first tap
                case "tap-start":
                    // Simulates a double-tap: warm-up on the first tap, start on the second.
                    dictation.warmUp(deviceID: currentMicrophone?.deviceID)
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        startDictation(dryRun: true)
                    }
                case "stop": dictation.stop()
                case "cancel": dictation.cancel()
                case "snapshot": snapshotMainWindow()
                case let command where command.hasPrefix("window:width:"):
                    if let width = Double(command.dropFirst("window:width:".count)),
                       let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "Audio Pencil" }) {
                        var frame = window.frame
                        frame.size.width = width
                        frame.size.height = 760
                        window.setFrame(frame, display: true)
                    }
                case "sidebar:toggle":
                    UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "sidebarCollapsed"), forKey: "sidebarCollapsed")
                case let command where command == "vault:read" || command.hasPrefix("vault:read:"):
                    // Logs the vault settings file (or vault:read:<vault-relative path>) as the app sees it.
                    Task {
                        guard let location = vault.vaultLocation else { return }
                        let path = command == "vault:read" ? ConfigSync.filePath(inVault: location.path) : StoragePath.join(location.path, String(command.dropFirst("vault:read:".count)))
                        let text = (try? await location.provider.read(path)).map { String(decoding: $0.data, as: UTF8.self) } ?? "(unreadable)"
                        Log.dictation.notice("Vault file \(path, privacy: .public):\n\(text, privacy: .public)")
                    }
                case let command where command.hasPrefix("vault:addword:") || command.hasPrefix("vault:removeword:"):
                    // Simulates an edit made in Obsidian: changes the vocabulary list in the file directly.
                    let word = String(command.split(separator: ":", maxSplits: 2).last ?? "")
                    let adding = command.hasPrefix("vault:addword:")
                    Task {
                        guard let location = vault.vaultLocation else { return }
                        let path = ConfigSync.filePath(inVault: location.path)
                        guard let (data, etag) = try? await location.provider.read(path),
                              var config = try? ConfigDocument.parse(String(decoding: data, as: UTF8.self)) else { return }
                        if adding { config.vocabulary.append(word) } else { config.vocabulary.removeAll { $0 == word } }
                        let wrote = (try? await location.provider.write(path, data: Data(ConfigDocument.render(config).utf8), ifMatch: etag, createOnly: false)) != nil
                        Log.dictation.notice("Simulated Obsidian edit (\(adding ? "add" : "remove") \(word, privacy: .public)): \(wrote ? "written" : "failed", privacy: .public)")
                    }
                case "vault:sync": sync.syncSoon(after: .zero)
                case let command where command.hasPrefix("longform-threshold:"):
                    debugLongFormThreshold = Double(command.dropFirst("longform-threshold:".count))
                    applyNoteSettings()
                case "review": notes.review()
                case "models:check": Task { await advisor.check() }
                case let command where command.hasPrefix("models:try:"):
                    let id = String(command.dropFirst("models:try:".count))
                    if let suggestion = advisor.suggestions.first(where: { $0.id == id }) { advisor.tryOut(suggestion) }
                case "models:report":
                    Log.models.notice("Suggestions: \(self.advisor.suggestions.map { "\($0.id) [\($0.kind.rawValue), \($0.sizeDescription)]" }.joined(separator: "; "), privacy: .public)")
                    for (id, trial) in self.advisor.trials {
                        switch trial {
                        case .done(let lines):
                            for line in lines {
                                Log.models.notice("Trial \(id, privacy: .public) – \(line.label, privacy: .public)\nNEW (\(line.candidateSeconds, format: .fixed(precision: 1))s): \(line.candidate, privacy: .public)\nCURRENT (\(line.currentSeconds, format: .fixed(precision: 1))s): \(line.current, privacy: .public)")
                            }
                        default:
                            Log.models.notice("Trial \(id, privacy: .public): \(String(describing: trial), privacy: .public)")
                        }
                    }
                case "review:skip": if let first = notes.pending.first { notes.skip(first) }
                case "review:approve":
                    if let first = notes.pending.first { notes.approve(first, title: first.note.title, tags: first.note.tags, folder: first.note.folder) }
                case "report:vocabulary":
                    Log.dictation.notice("App vocabulary: \(self.settings.customVocabulary.joined(separator: ", "), privacy: .public); sync \(String(describing: self.sync.status), privacy: .public)")
                case let command where command.hasPrefix("mouse:") || command.hasPrefix("click:"):
                    // Synthetic pointer input at the indicator (moves the real cursor):
                    // mouse:chip, click:chip, mouse:above, click:<style id> (picker choice).
                    let target = String(command.split(separator: ":").last ?? "")
                    if command == "mouse:restore" {
                        if let saved = debugSavedCursor {
                            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: saved, mouseButton: .left)?.post(tap: .cghidEventTap)
                            debugSavedCursor = nil
                        }
                        break
                    }
                    let pickerID = ["chip", "above"].contains(target) ? nil : target
                    guard let point = indicatorPanel?.debugPoint(chip: target == "chip", pickerStyleID: pickerID) else { break }
                    if debugSavedCursor == nil { debugSavedCursor = CGEvent(source: nil)?.location }
                    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                    if command.hasPrefix("click:") {
                        // Post asynchronously: the click opens a menu whose tracking loop blocks this handler.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                            }
                        }
                    }
                case let command where command.hasPrefix("real:"):
                    // Real key events through the system (and our tap): real:down, real:return.
                    let codes: [String: CGKeyCode] = ["down": 125, "up": 126, "return": 36, "escape": 53]
                    if let code = codes[String(command.dropFirst(5))] {
                        for isDown in [true, false] {
                            CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: isDown)?.post(tap: .cghidEventTap)
                        }
                    }
                case "report":
                    Log.dictation.notice("Report: frontmost \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "–", privacy: .public), Audio Pencil active \(NSApp.isActive), menu open \(self.indicator.isMenuOpen), panel ignores mouse \(self.indicatorPanel?.debugIgnoresMouse ?? true), style \(self.dictation.style.name, privacy: .public), phase \(String(describing: self.dictation.phase), privacy: .public)")
                case let command where command.hasPrefix("key:"):
                    // Simulated hotkey input through the real gesture logic: key:fnDown, key:fnUp, key:other, key:escape, key:return.
                    let events: [String: HotkeyMonitor.KeyEvent] = ["fnDown": .fnDown, "fnUp": .fnUp, "other": .other, "escape": .escape, "return": .returnKey]
                    let name = String(command.dropFirst(4))
                    if let event = events[name] ?? Int(name).map(HotkeyMonitor.KeyEvent.digit) {
                        debugDryRunUntil = Date().addingTimeInterval(30)
                        _ = handle(event, at: ProcessInfo.processInfo.systemUptime)
                    }
                case let command where command.hasPrefix("page:"):
                    page = Page(rawValue: String(command.dropFirst(5))) ?? page
                default: break
                }
            }
        }
    }

    /// Writes the main window (including title bar) to Application Support/AudioPencil/Debug/snapshot.png,
    /// so UI changes can be checked without screen-recording permission.
    private func snapshotMainWindow() {
        if let review = NSApp.windows.first(where: { $0.isVisible && $0.title == "Review note" }),
           let view = review.contentView?.superview, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            let folder = ModelLocations.root.deletingLastPathComponent().appending(path: "Debug")
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: "review.png"))
        }
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "Audio Pencil" }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let folder = ModelLocations.root.deletingLastPathComponent().appending(path: "Debug")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "snapshot.png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        Log.dictation.notice("Snapshot written to \(url.path, privacy: .public)")
        // The floating indicator too, when it's showing.
        if let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }), let view = panel.contentView,
           let panelRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: panelRep)
            try? panelRep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: "indicator.png"))
        }
    }
    #endif

    /// Accessibility has no change notification, so poll until everything needed is granted.
    private func pollPermissions() {
        permissionPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                permissions.refresh()
                startHotkeysIfPossible()
            }
        }
    }

    private func startHotkeysIfPossible() {
        guard !hotkeys.isActive, permissions.accessibility else {
            hotkeyActive = hotkeys.isActive
            return
        }
        hotkeyActive = hotkeys.start()
    }

    // MARK: Model

    func prepareModel() {
        let engine = whisper
        let vocabulary = settings.customVocabulary
        modelTask = Task {
            await engine.setVocabulary(vocabulary)
            do {
                if !engine.isDownloaded {
                    modelState = .downloading(0)
                    try await engine.download { fraction in
                        Task { @MainActor [weak self] in
                            if case .downloading = self?.modelState { self?.modelState = .downloading(fraction) }
                        }
                    }
                }
                modelState = .loading(firstTime: engine.needsFirstTimePreparation)
                try await coordinator.ensureLoaded(engine)
                if engine === whisper { modelState = .ready }
            } catch {
                if engine === whisper { modelState = .failed(error.localizedDescription) }
                throw error
            }
        }
    }

    private func waitForModel() async throws {
        if modelTask == nil { prepareModel() }
        try await modelTask?.value
    }

    private func switchModel(to variant: String) {
        let old = whisper
        whisper = WhisperEngine(variant: variant)
        modelState = .idle
        Task {
            await coordinator.unload(old)
            prepareModel()
        }
    }

    // MARK: Hotkeys

    /// Returns true to swallow the key event.
    private func handle(_ event: HotkeyMonitor.KeyEvent, at time: TimeInterval) -> Bool {
        // The style menu is open: Return, Esc and number keys belong to it.
        if indicator.isMenuOpen {
            switch event {
            case .escape, .returnKey, .digit: return false
            default: break
            }
        }
        switch event {
        case .fnDown:
            _ = detector.handle(.keyDown(at: time))
            scheduleHoldCheck()
            return false
        case .fnUp:
            holdTask?.cancel()
            if holdRecording {
                holdRecording = false
                _ = detector.handle(.keyUp(at: time))
                detector.reset()
                trace("→ Fn released: stop (raw)")
                dictation.stop()
                return false
            }
            if let gesture = detector.handle(.keyUp(at: time)) {
                handle(gesture)
            } else {
                trace("→ not a tap (held too long, or another key in between)")
            }
            return false
        case .other:
            _ = detector.handle(.otherInput)
            holdTask?.cancel()
            if holdRecording {
                // Fn was being used as a modifier after all (Fn+arrow): drop the recording, pass the key on.
                holdRecording = false
                trace("→ another key during hold: cancelled")
                dictation.cancel()
            }
            return false
        case .escape:
            guard dictation.isActive else { return false }
            dictation.cancel()
            return true
        case .returnKey:
            if dictation.isPicking {
                dictation.confirmPick()
                return true
            }
            guard dictation.phase == .recording, settings.returnStops else { return false }
            dictation.stop()
            return true
        case .digit(let number):
            if dictation.isPicking {
                if let style = enabledStyle(shortcut: number) { dictation.pick(style) }
                return true
            }
            guard dictation.phase == .recording || dictation.phase == .starting else { return false }
            if let style = enabledStyle(shortcut: number) {
                trace("→ \(number): \(style.name)")
                dictation.select(style)
            }
            return true // swallow digits while recording so they don't type into the field
        case .fallbackShortcut:
            guard settings.fallbackShortcutEnabled else { return false }
            switch dictation.phase {
            case .idle: startDictation()
            case .recording: dictation.stop()
            case .starting, .finishing: break
            }
            return true
        }
    }

    private func handle(_ gesture: FnTapDetector.Gesture) {
        switch (dictation.phase, gesture, settings.stopGesture) {
        case (.idle, .singleTap, _) where settings.warmMicOnFirstTap && permissions.microphone == .granted:
            trace("→ tap: warming up the mic")
            dictation.warmUp(deviceID: currentMicrophone?.deviceID)
        case (.idle, .doubleTap, _):
            trace("→ double-tap: start recording")
            detector.reset()
            startDictation()
        case (.recording, .singleTap, .singleTapFn), (.recording, .doubleTap, .doubleTapFn):
            trace("→ \(gesture == .singleTap ? "tap" : "double-tap"): stop")
            detector.reset()
            dictation.stop()
        default:
            trace("→ \(gesture == .singleTap ? "tap" : "double-tap") (no action while \(dictation.phase))")
        }
    }

    /// Press-and-hold push-to-talk: if Fn is still held cleanly after the threshold, record raw until release.
    private func scheduleHoldCheck() {
        guard settings.holdFnForRaw, dictation.phase == .idle else { return }
        holdTask?.cancel()
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.holdThreshold))
            guard let self, !Task.isCancelled, dictation.phase == .idle,
                  detector.isHeld(for: Self.holdThreshold, at: ProcessInfo.processInfo.systemUptime)
            else { return }
            holdRecording = true
            trace("→ Fn held: recording until release (raw)")
            startDictation(raw: true)
        }
    }

    private func trace(_ text: String) {
        let now = ProcessInfo.processInfo.systemUptime
        if let origin = traceOrigin, now - origin < 3 {
            hotkeyTrace.append(String(format: "+%4.0f ms  ", (now - origin) * 1000) + text)
        } else {
            traceOrigin = now
            hotkeyTrace.append("     0 ms  " + text)
        }
        hotkeyTrace = Array(hotkeyTrace.suffix(12))
        Log.hotkey.notice("\(text, privacy: .public)")
    }

    /// Menu bar item: start when idle, stop when recording.
    func toggleDictation() {
        switch dictation.phase {
        case .idle: startDictation()
        case .recording: dictation.stop()
        case .starting, .finishing: break
        }
    }

    /// `raw`: push-to-talk. Otherwise the style remembered for the frontmost app.
    private func startDictation(dryRun: Bool = false, raw: Bool = false) {
        guard dictation.phase == .idle else { return }
        #if DEBUG
        dictation.dryRun = dryRun || Date() < debugDryRunUntil
        #else
        dictation.dryRun = dryRun
        #endif
        permissions.refresh()
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let style = raw ? Style.raw : styleMemory.defaultStyle(forApp: app, among: styles)
        dictation.start(
            microphoneGranted: permissions.microphone == .granted,
            deviceID: currentMicrophone?.deviceID,
            style: style,
            targetApp: app,
            remembersStyle: !raw
        )
    }

    // MARK: Settings

    private static func loadSettings() -> DictationSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(DictationSettings.self, from: data)
        else { return DictationSettings() }
        return settings
    }

    private func settingsChanged(from old: DictationSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        detector.configuration.maxGapBetweenTaps = settings.doubleTapWindow
        indicator.showLiveText = settings.showLiveText
        if settings.transcriptionModel != old.transcriptionModel {
            switchModel(to: settings.transcriptionModel)
        } else if settings.customVocabulary != old.customVocabulary {
            let engine = whisper
            let vocabulary = settings.customVocabulary
            Task { await engine.setVocabulary(vocabulary) }
        }
        if settings.menuBarMode != old.menuBarMode {
            applyAppPresence()
        }
        applyNoteSettings()
        if !applyingSync { sync?.syncSoon() }
        if settings.writingModel != old.writingModel {
            switchWritingModel(to: settings.writingModel)
        }
        applyPickerSettings()
    }

    private func applyNoteSettings() {
        dictation?.longFormThreshold = debugLongFormThreshold ?? settings.longFormThreshold
        dictation?.savesQuickDictations = settings.saveQuickDictations
        dictation?.setSounds(theme: CueTheme(rawValue: settings.cueTheme) ?? .tricorder, volume: settings.cueVolume)
    }

    // MARK: App presence

    /// Dock icon (default) or menu-bar-only.
    private func applyAppPresence() {
        NSApp.setActivationPolicy(settings.menuBarMode ? .accessory : .regular)
        if !settings.menuBarMode { NSApp.activate() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.dictation.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        launchAtLoginNeedsApproval = status == .requiresApproval
    }
}
