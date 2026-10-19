import APCore
import APModels
import APTranscription
import AppKit

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

    var settings: DictationSettings {
        didSet { settingsChanged(from: oldValue) }
    }

    let permissions = Permissions()
    let indicator = IndicatorModel()
    private(set) var modelState: TranscriptionModelState = .idle
    private(set) var hotkeyActive = false
    private(set) var lastKeyDiagnostic = "Press Fn to test"
    private(set) var memoryPressure: MemoryPressureMonitor.Level = .normal
    private(set) var whisper: WhisperEngine

    @ObservationIgnored let coordinator = ModelCoordinator()
    @ObservationIgnored private(set) var dictation: DictationController!
    @ObservationIgnored private let hotkeys = HotkeyMonitor()
    @ObservationIgnored private var detector: FnTapDetector
    @ObservationIgnored private var indicatorPanel: IndicatorPanelController?
    @ObservationIgnored private var modelTask: Task<Void, any Error>?
    @ObservationIgnored private var memoryMonitor: MemoryPressureMonitor?
    @ObservationIgnored private var permissionPoll: Task<Void, Never>?

    init() {
        let settings = Self.loadSettings()
        self.settings = settings
        self.whisper = WhisperEngine(variant: settings.transcriptionModel)
        self.detector = FnTapDetector(configuration: .init(maxGapBetweenTaps: settings.doubleTapWindow))
        self.dictation = DictationController(
            indicator: indicator,
            engine: { [unowned self] in whisper },
            waitForModel: { [unowned self] in try await waitForModel() }
        )
        indicator.showLiveText = settings.showLiveText
    }

    // MARK: Lifecycle

    func bootstrap() {
        indicatorPanel = IndicatorPanelController(model: indicator)
        hotkeys.handler = { [unowned self] event, time in handle(event, at: time) }
        hotkeys.onDiagnostic = { [unowned self] text in lastKeyDiagnostic = text }
        memoryMonitor = MemoryPressureMonitor { level in
            Task { @MainActor [weak self] in self?.memoryPressure = level }
        }
        permissions.refresh()
        startHotkeysIfPossible()
        prepareModel()
        pollPermissions()
    }

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
        modelTask = Task {
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
        switch event {
        case .fnDown:
            _ = detector.handle(.keyDown(at: time))
            return false
        case .fnUp:
            if let gesture = detector.handle(.keyUp(at: time)) { handle(gesture) }
            return false
        case .other:
            _ = detector.handle(.otherInput)
            return false
        case .escape:
            guard dictation.isActive else { return false }
            dictation.cancel()
            return true
        case .returnKey:
            guard dictation.phase == .recording, settings.returnStops else { return false }
            dictation.stop()
            return true
        case .fallbackShortcut:
            guard settings.fallbackShortcutEnabled else { return false }
            switch dictation.phase {
            case .idle: startDictation()
            case .recording: dictation.stop()
            case .finishing: break
            }
            return true
        }
    }

    private func handle(_ gesture: FnTapDetector.Gesture) {
        switch (dictation.phase, gesture, settings.stopGesture) {
        case (.idle, .doubleTap, _):
            detector.reset()
            startDictation()
        case (.recording, .singleTap, .singleTapFn), (.recording, .doubleTap, .doubleTapFn):
            detector.reset()
            dictation.stop()
        default:
            break
        }
    }

    private func startDictation() {
        permissions.refresh()
        dictation.start(microphoneGranted: permissions.microphone == .granted)
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
        }
    }
}
