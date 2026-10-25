import APAudio
import APCore
import APModels
import APStorage
import APSummary
import APSync
import APTranscription
import AppKit
import ServiceManagement

/// App-wide state and wiring: settings, permissions, the speech model, hotkeys and the dictation loop.
@Observable
final class AppModel: WritingHost {
    static let settingsKey = "dictationSettings"
    static let statsKey = "usageStats"
    static let stylesKey = "styles"
    static let styleMemoryKey = "styleMemory"

    /// Page shown in the main window.
    var page: Page = .dictation
    var settingsTab: SettingsTab = .general

    /// Settings › Permissions (what used to be the Setup page).
    func openPermissions() {
        settingsTab = .permissions
        page = .settings
    }
    /// Counts only, for the stats column.
    private(set) var stats: UsageStats = AppModel.loadStats()

    /// Something the hotkey needs is missing.
    var needsSetup: Bool {
        !permissions.allRequiredGranted || !hotkeyActive || (settings.gestureKey == .fn && !permissions.fnKeyIsFree)
    }

    /// How to start a dictation, e.g. "Double-tap Fn", for hints and status lines.
    var startHint: String { settings.startGesture.label(settings.gestureKey) }

    var settings: DictationSettings {
        didSet { settingsChanged(from: oldValue) }
    }

    let permissions = Permissions()
    let indicator = IndicatorModel()
    let vault = VaultController()
    @ObservationIgnored private(set) var sync: SyncController!
    @ObservationIgnored private(set) var notes: NoteMaker!
    @ObservationIgnored private(set) var meetings: MeetingController!
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
    /// Dictations starting with one of these become an Obsidian task. Shared through the settings file.
    var taskKeywords: [String] = UserDefaults.standard.stringArray(forKey: "taskKeywords") ?? TaskKeywords.defaults {
        didSet {
            UserDefaults.standard.set(taskKeywords, forKey: "taskKeywords")
            dictation?.taskKeywords = taskKeywords
            if !applyingSync, taskKeywords != oldValue { sync?.syncSoon() }
        }
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
    /// The speech model for the active language: Whisper, or Phonon-2 for English while trying it out.
    private(set) var speech: any DictationEngine
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
    /// Language last spoken in each app, on this Mac only.
    var languageMemory: LanguageMemory {
        didSet { saveLanguageMemory() }
    }
    /// The language Whisper is set up for: the next recording's, or the current one's.
    var activeLanguage: SpokenLanguage = .english
    /// 0…1 while the multilingual model downloads in the background; nil otherwise.
    var multilingualDownload: Double?
    /// A first-time model preparation in progress (step, clock, estimate), for every status display.
    var preparation: ModelPreparation?
    @ObservationIgnored var preparationActivity: (any NSObjectProtocol)?
    /// Background preparation of other languages' models, and the model it's working on.
    @ObservationIgnored var multilingualQueue: Task<Void, Never>?
    @ObservationIgnored var multilingualJob: Task<Void, Never>?
    @ObservationIgnored var multilingualDownloadVariant: String?
    /// Languages already told (this run) that they're on the starter model.
    @ObservationIgnored var starterNoteShown: Set<String> = []
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
        currentMicrophone?.name ?? MicrophoneCatalog.systemDefault(among: microphones)?.name ?? String(localized: "System default")
    }

    var currentMicrophoneName: String {
        if let currentMicrophone { return currentMicrophone.name }
        let fallback = MicrophoneCatalog.systemDefault(among: microphones)?.name ?? "unknown"
        return String(localized: "System default (\(fallback))")
    }

    @ObservationIgnored let coordinator = ModelCoordinator()
    @ObservationIgnored private(set) var dictation: DictationController!
    @ObservationIgnored private let hotkeys = HotkeyMonitor()
    @ObservationIgnored private var detector: FnTapDetector
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    /// A press-and-hold recording is running; releasing Fn stops it.
    @ObservationIgnored private var holdRecording = false
    #if DEBUG
    /// Simulated key presses from the debug hook make dictations dry runs until this time.
    @ObservationIgnored private var debugDryRunUntil = Date.distantPast
    @ObservationIgnored private var debugSavedCursor: CGPoint?
    #endif
    @ObservationIgnored private var indicatorPanel: IndicatorPanelController?
    @ObservationIgnored var modelTask: Task<Void, any Error>?
    @ObservationIgnored private var memoryMonitor: MemoryPressureMonitor?
    @ObservationIgnored private var permissionPoll: Task<Void, Never>?
    @ObservationIgnored private var debugObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var microphoneCatalog: MicrophoneCatalog?
    @ObservationIgnored var writingTask: Task<Void, Never>?
    /// No sign of an earlier install when the app started: setup runs instead of the main window.
    let isFirstLaunch: Bool
    @ObservationIgnored var setupWindow: NSWindow?
    var setupStep: SetupStep = .welcome
    @ObservationIgnored var setupCloseObserver: (any NSObjectProtocol)?

    init() {
        isFirstLaunch = Self.checkFirstLaunch() // before anything below saves settings
        let settings = Self.loadSettings()
        self.settings = settings
        let memory = Self.loadLanguageMemory()
        self.languageMemory = memory
        self.activeLanguage = memory.language(forApp: nil)
        self.speech = Self.engine(for: Self.bestVariant(for: memory.language(forApp: nil), settings: settings))
        self.writing = SummaryEngine(modelID: settings.writingModel)
        self.styles = Self.loadStyles()
        self.styleMemory = Self.loadStyleMemory()
        self.detector = FnTapDetector(configuration: .init(maxGapBetweenTaps: settings.doubleTapWindow))
        self.dictation = DictationController(
            indicator: indicator,
            engine: { [unowned self] in speech },
            waitForModel: { [unowned self] in try await waitForModel() },
            rewrite: { [unowned self] transcript, style, progress in
                try await rewrite(transcript, style: style, progress: progress)
            }
        )
        indicator.showLiveText = settings.showLiveText
        dictation.onStyleUsed = { [unowned self] style, app in styleMemory.remember(style.id, forApp: app) }
        dictation.onLanguageUsed = { [unowned self] language, app in languageMemory.remember(language, forApp: app) }
        dictation.onLanguageSelected = { [unowned self] language in useLanguage(language) }
        sync = SyncController(vault: vault)
        sync.localConfig = { [unowned self] base in localConfig(from: base) }
        sync.apply = { [unowned self] config in apply(config) }
        sync.retentionFolders = { [unowned self] in
            Array(Set(styles.map { notes.folder(for: $0) } + [NoteMaker.defaultFolder, StarterKit.samplesFolder]))
        }
        sync.expireRegularAudio = { [unowned self] in expireRegularAudio }
        sync.filedNotePaths = { [unowned self] in notes.recent.map(\.path) + (meetings?.sessions.compactMap(\.notePath) ?? []) }
        sync.filedNotesGone = { [unowned self] paths in
            notes.forget(paths)
            meetings?.forget(paths)
        }
        vault.onLocationReady = { [unowned self] in sync.syncSoon(after: .zero) }
        vault.onLayoutChanged = { [unowned self] in sync.layoutChanged() }
        notes = NoteMaker(app: self)
        meetings = MeetingController(app: self)
        indicator.onOpenMeeting = { [weak self] in self?.openMeetings() }
        indicator.onPauseMeeting = { [weak self] in Task { await self?.meetings.togglePause() } }
        indicator.onStopMeeting = { [weak self] in Task { await self?.meetings.stop() } }
        notes.onOpenMeeting = { [weak self] id in
            self?.meetings.selectedID = id
            self?.openMeetings()
        }
        advisor = ModelAdvisor(app: self)
        dictation.onLongForm = { [unowned self] capture in notes.makeLongFormNote(capture) }
        dictation.onPushToTalkText = { [unowned self] text, destination, said in addPushToTalkLine(text, to: destination, said: said) }
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
        applyHotkeySettings()
        hotkeys.onDiagnostic = { [unowned self] text in trace(text) }
        memoryMonitor = MemoryPressureMonitor { level in
            Task { @MainActor [weak self] in self?.memoryPressure = level }
        }
        microphoneCatalog = MicrophoneCatalog { microphones in
            Task { @MainActor [weak self] in self?.microphones = microphones }
        }
        applyAppPresence()
        prepareInBackground()
        sync.isHeld = isFirstLaunch
        sync.start()
        permissions.refresh()
        startHotkeysIfPossible()
        if isFirstLaunch {
            showSetup(hidingMainWindow: true) // the English model starts on its Permissions step
        } else {
            if needsSetup { openPermissions() }
            prepareModel()
        }
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
                case "phonon:on", "phonon:off", "phonon:force":
                    Self.debugPhononIgnoresVocabulary = command == "phonon:force"
                    phononTrial = command != "phonon:off"
                case "snapshot": snapshotMainWindow()
                case let command where command.hasPrefix("settings:"):
                    if let tab = SettingsTab(rawValue: String(command.dropFirst("settings:".count))) {
                        settingsTab = tab
                        page = .settings
                    }
                case "meeting:fixture":
                    page = .meetings
                    Task { await meetings.importDebugFixture() }
                case "meeting:remove-fixtures": meetings.removeDebugFixtures()
                case "meeting:video-call": meetings.kind = .videoCall
                case "meeting:in-person": meetings.kind = .inPerson
                case "meeting:report":
                    let meeting = meetings.selected
                    Log.dictation.notice("Meeting: capture \(String(describing: self.meetings.capture), privacy: .public), stage \(meeting?.stage.rawValue ?? "none", privacy: .public), turns \(meeting?.turns.count ?? 0), summary \(meeting?.summary.count ?? 0) characters, error \(self.meetings.error ?? "none", privacy: .public)")
                case "window:report":
                    if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "Audio Pencil" }) {
                        Log.dictation.notice("Window sizing: width \(window.frame.width), maximum width \(window.maxSize.width), maximum height \(window.maxSize.height)")
                    }
                case let command where command.hasPrefix("window:width:"):
                    if let width = Double(command.dropFirst("window:width:".count)),
                       let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "Audio Pencil" }) {
                        var frame = window.frame
                        frame.size.width = width
                        frame.size.height = 760
                        window.setFrame(frame, display: true)
                    }
                case let command where command.hasPrefix("languages:"):
                    // e.g. languages:en,fr,es — the list offered in the pill and Settings.
                    settings.dictationLanguages = command.dropFirst("languages:".count).split(separator: ",").map(String.init)
                case let command where command.hasPrefix("language:"):
                    // Switches the recording's language, or the default when idle (as Settings does).
                    let language = SpokenLanguage(code: String(command.dropFirst("language:".count)))
                    if dictation.phase == .idle { chooseDefaultLanguage(language) } else { dictation.select(language) }
                case "report:language":
                    Log.dictation.notice("Language: active \(self.activeLanguage.code, privacy: .public), speech \(self.speech.variant, privacy: .public), offered \(self.offeredLanguages.map(\.code).joined(separator: ","), privacy: .public), memory \(String(describing: self.languageMemory), privacy: .public)")
                case let command where command.hasPrefix("scroll:"):
                    // Scrolls the main window's page, so captures can reach content below the fold.
                    if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "Audio Pencil" }),
                       let content = window.contentView {
                        func scrollViews(in view: NSView) -> [NSScrollView] {
                            (view as? NSScrollView).map { [$0] } ?? [] + view.subviews.flatMap(scrollViews)
                        }
                        if let page = scrollViews(in: content).max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
                           let document = page.documentView {
                            let clip = page.contentView
                            let bottom = document.isFlipped ? max(0, document.frame.height - clip.bounds.height) : 0
                            let top = document.isFlipped ? 0 : max(0, document.frame.height - clip.bounds.height)
                            let offset = Double(command.dropFirst("scroll:".count)).map { CGFloat($0) }
                            let y = offset.map { document.isFlipped ? min($0, bottom) : max(top - $0, 0) } ?? (command == "scroll:end" ? bottom : top)
                            clip.scroll(to: NSPoint(x: 0, y: y))
                            page.reflectScrolledClipView(clip)
                        }
                    }
                case "appearance:light", "appearance:dark", "appearance:system":
                    // This app only; the system appearance is left alone.
                    NSApp.appearance = switch command {
                    case "appearance:light": NSAppearance(named: .aqua)
                    case "appearance:dark": NSAppearance(named: .darkAqua)
                    default: nil
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
                case "setup": showSetup(hidingMainWindow: false)
                case "setup:close": setupWindow?.close()
                case "delivery:toggle": dictation.toggleDelivery()
                case "push:cycle": dictation.cyclePushDestination()
                case "daily:toggle": dictation.toggleDailyNote()
                case let command where command.hasPrefix("paste:"):
                    // The real paste path into the frontmost app, for measuring confirmation per app.
                    let text = String(command.dropFirst("paste:".count))
                    Task {
                        let outcome = await dictation.paster.deliver(text)
                        Log.dictation.notice("Paste test in \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?", privacy: .public): \(outcome.rawValue, privacy: .public)")
                    }
                case "report:windows":
                    for window in NSApp.windows {
                        Log.dictation.notice("Window \(window.identifier?.rawValue ?? "-", privacy: .public) “\(window.title, privacy: .public)” visible \(window.isVisible)")
                    }
                case let command where command.hasPrefix("setup:"):
                    let name = command.dropFirst("setup:".count)
                    if let step = SetupStep.allCases.first(where: { "\($0)" == name }) { setupStep = step }
                case "vault:adopt": vault.adoptObsidianLayout()
                case "note:keep", "note:delete": // the first recent note, as the Notes page's menu does
                    if let note = notes.recent.first { notes.setRetention(command == "note:keep" ? .archive : .delete, for: note) }
                case let command where command.hasPrefix("longform-threshold:"):
                    debugLongFormThreshold = Double(command.dropFirst("longform-threshold:".count))
                    applyNoteSettings()
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
        for name in ["setup"] {
            guard let other = NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue == name }),
                  let view = other.contentView?.superview, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let folder = ModelLocations.root.deletingLastPathComponent().appending(path: "Debug")
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: "\(name).png"))
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

    /// Loads the current speech model; `old` (a model being switched away from) is unloaded first.
    /// `modelTask` is replaced right away, so anything waiting for a model waits for this one.
    func prepareModel(unloading old: (any DictationEngine)? = nil) {
        guard meetings?.isProcessing != true else { return }
        let engine = speech
        let vocabulary = settings.vocabulary(for: activeLanguage)
        let language = activeLanguage
        // Already fetching this model in the background: wait for that rather than fetch it twice.
        let prefetch = multilingualDownloadVariant == engine.variant ? multilingualJob : nil
        modelTask = Task {
            if let old { await coordinator.unload(old) }
            await observePreparation(of: engine)
            await prefetch?.value
            await engine.setVocabulary(vocabulary)
            await engine.setLanguage(language.code)
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
                if engine === speech { modelState = .ready }
            } catch {
                if engine === speech { modelState = .failed(error.localizedDescription) }
                throw error
            }
        }
    }

    private func waitForModel() async throws {
        if modelTask == nil { prepareModel() }
        // A model switch while waiting replaces modelTask: keep waiting for whichever is current.
        while let task = modelTask {
            try await task.value
            if task == modelTask { break }
        }
    }

    func switchModel(to variant: String) {
        let old = speech
        speech = Self.engine(for: variant)
        modelState = .idle
        prepareModel(unloading: old)
    }

    // MARK: Hotkeys

    /// Returns true to swallow the key event.
    private func handle(_ event: HotkeyMonitor.KeyEvent, at time: TimeInterval) -> Bool {
        if meetings.ownsCapture || meetings.isProcessing {
            holdTask?.cancel()
            holdRecording = false
            detector.reset()
            return false
        }
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
        switch (dictation.phase, gesture, settings.effectiveStopGesture) {
        case (.idle, .singleTap, _) where settings.startGesture == .singleTap:
            trace("→ tap: start recording")
            detector.reset()
            startDictation()
        case (.idle, .singleTap, _) where settings.warmMicOnFirstTap && permissions.microphone == .granted:
            trace("→ tap: warming up the mic")
            dictation.warmUp(deviceID: currentMicrophone?.deviceID)
        case (.idle, .doubleTap, _) where settings.startGesture == .doubleTap:
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
        let delay = settings.pushToTalkDelay
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, dictation.phase == .idle,
                  settings.holdFnForRaw,
                  detector.isHeld(for: delay, at: ProcessInfo.processInfo.systemUptime)
            else { return }
            holdRecording = true
            trace("→ Fn held: recording until release (raw)")
            startDictation(raw: true)
        }
    }

    private func applyHotkeySettings() {
        hotkeys.gestureKey = settings.gestureKey
        hotkeys.shortcut = settings.fallbackShortcut
    }

    /// Settings is recording a new shortcut: the event tap stands aside until it's done.
    func pauseHotkeys(_ paused: Bool) {
        hotkeys.isPaused = paused
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
    /// Push-to-talk text in the daily note or a file: "- 14:32 the text", or a task line as it is (a task
    /// keeps no time stamp, so it reads as a task).
    func addPushToTalkLine(_ text: String, to destination: PushDestination, said: Date) {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
        let line = oneLine.hasPrefix(TaskLine.checkbox) ? oneLine : "- " + DailyNoteEntry.clock(said) + " " + oneLine
        let target: PendingAppend.Target = switch destination {
        case .dailyNote: .dailyNote(said)
        case .file(let path): .file(path)
        }
        sync.append(line, to: target, heading: settings.pushToTalkHeading)
    }

    /// Menu bar "Record a Meeting": a recording that becomes a meeting note, speakers labelled.
    func startMeeting() {
        openMeetings()
    }

    func openMeetings() {
        page = .meetings
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.title == "Audio Pencil" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// The Whisper model in use, loaded (speaker labels need its word timings).
    func waitForSpeechModel() async throws {
        try await waitForModel()
    }

    func toggleDictation() {
        switch dictation.phase {
        case .idle: startDictation()
        case .recording: dictation.stop()
        case .starting, .finishing: break
        }
    }

    /// `raw`: push-to-talk. Otherwise the style remembered for the frontmost app.
    private func startDictation(dryRun: Bool = false, raw: Bool = false) {
        guard dictation.phase == .idle, !meetings.ownsCapture, !meetings.isProcessing else { return }
        meetings.endPreview()
        #if DEBUG
        dictation.dryRun = dryRun || Date() < debugDryRunUntil
        #else
        dictation.dryRun = dryRun
        #endif
        permissions.refresh()
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let style = raw ? Style.raw : styleMemory.defaultStyle(forApp: app, among: styles)
        let language = languageMemory.language(forApp: app)
        if language != activeLanguage || speech.variant != transcriptionVariant(for: language) {
            useLanguage(language) // the mic starts meanwhile; transcription catches up once the model is in
        }
        indicator.languageChoices = offeredLanguages
        indicator.note = starterNote(for: language)
        // Daily note: the setting's default for a note, if the vault has Daily notes on.
        indicator.dailyNoteAvailable = sync.dailyNotes == .on
        indicator.dailyNoteDefault = settings.dailyNoteLinks
        // Push-to-talk only pastes unless a destination is picked on the pill; offer what exists.
        var destinations: [PushDestination] = []
        if raw {
            if sync.dailyNotes == .on { destinations.append(.dailyNote) }
            let file = settings.pushToTalkFile.trimmingCharacters(in: .whitespaces)
            if !file.isEmpty, vault.settings.isConfigured { destinations.append(.file(file)) }
        }
        indicator.pushChoices = destinations
        dictation.start(
            microphoneGranted: permissions.microphone == .granted,
            deviceID: currentMicrophone?.deviceID,
            style: style,
            language: language,
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
        applyHotkeySettings()
        indicator.showLiveText = settings.showLiveText
        if speech.variant != transcriptionVariant(for: activeLanguage) {
            switchModel(to: transcriptionVariant(for: activeLanguage))
        } else if settings.vocabulary(for: activeLanguage) != old.vocabulary(for: activeLanguage) {
            let engine = speech
            let vocabulary = settings.vocabulary(for: activeLanguage)
            Task { await engine.setVocabulary(vocabulary) }
        }
        indicator.languageChoices = offeredLanguages
        if settings.dictationLanguages != old.dictationLanguages || settings.multilingualTranscriptionModel != old.multilingualTranscriptionModel {
            prepareInBackground()
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
        dictation?.taskKeywords = taskKeywords
        dictation?.paster.keepsClipboard = settings.keepClipboard
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
