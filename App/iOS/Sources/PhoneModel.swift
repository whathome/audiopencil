import APCore
import APModels
import APStorage
import APSummary
import APSync
import APTranscription
import Foundation
import Observation

/// The iPhone app's state and wiring: settings and styles (shared with the Mac through the vault settings
/// file), storage and sync, the Whisper and writing models, the recorder and notes.
@Observable
final class PhoneModel: WritingHost {
    static let settingsKey = "dictationSettings"
    static let stylesKey = "styles"
    static let samplesKey = "writingSamples"
    static let languageMemoryKey = "languageMemory"
    static let lastStyleKey = "lastStyle"
    static let setupCompletedKey = "setupCompleted"

    var settings: DictationSettings {
        didSet { settingsChanged(from: oldValue) }
    }
    var styles: [Style] {
        didSet { saveStyles(from: oldValue) }
    }
    /// Master tag list from the vault settings file.
    var tags: [String] = [] {
        didSet { if !applyingSync, tags != oldValue { sync?.syncSoon() } }
    }
    /// Recordings starting with one of these become a one-line Obsidian task. Shared through the settings file.
    var taskKeywords: [String] = UserDefaults.standard.stringArray(forKey: "taskKeywords") ?? TaskKeywords.defaults {
        didSet {
            UserDefaults.standard.set(taskKeywords, forKey: "taskKeywords")
            if !applyingSync, taskKeywords != oldValue { sync?.syncSoon() }
        }
    }
    var writingSamples: [WritingSample] {
        didSet {
            save(writingSamples, as: Self.samplesKey)
            if !applyingSync, writingSamples != oldValue { sync?.syncSoon() }
        }
    }
    /// Vault-wide: remove "regular" audio a year after recording.
    var expireRegularAudio: Bool = UserDefaults.standard.object(forKey: "expireRegularAudio") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(expireRegularAudio, forKey: "expireRegularAudio")
            if !applyingSync, expireRegularAudio != oldValue { sync?.syncSoon() }
        }
    }
    /// The language of the last recording; the next one starts in it.
    var languageMemory: LanguageMemory {
        didSet { save(languageMemory, as: Self.languageMemoryKey) }
    }
    /// The style chosen last; the style sheet starts on it (iOS can't tell which app you came from).
    var lastStyleID: String = UserDefaults.standard.string(forKey: PhoneModel.lastStyleKey) ?? Style.polished.id {
        didSet { UserDefaults.standard.set(lastStyleID, forKey: Self.lastStyleKey) }
    }
    var setupCompleted: Bool = UserDefaults.standard.bool(forKey: PhoneModel.setupCompletedKey) {
        didSet { UserDefaults.standard.set(setupCompleted, forKey: Self.setupCompletedKey) }
    }

    // Recording on this iPhone (not synced).
    /// Apple's voice processing on the microphone: damps wind and traffic.
    var reduceNoise: Bool = UserDefaults.standard.object(forKey: "reduceNoise") as? Bool ?? true {
        didSet { UserDefaults.standard.set(reduceNoise, forKey: "reduceNoise") }
    }
    /// Stop after this long without new words (5 minutes at most).
    var autoStopMinutes: Int = UserDefaults.standard.object(forKey: "autoStopMinutes") as? Int ?? 5 {
        didSet { UserDefaults.standard.set(min(max(autoStopMinutes, 1), 5), forKey: "autoStopMinutes") }
    }
    /// A tap now and then while the phone is locked, to feel that it's still recording.
    var heartbeat: RecordingFeedback.Heartbeat = RecordingFeedback.Heartbeat(rawValue: UserDefaults.standard.string(forKey: "heartbeat") ?? "") ?? .tap {
        didSet { UserDefaults.standard.set(heartbeat.rawValue, forKey: "heartbeat") }
    }
    var heartbeatMinutes: Int = UserDefaults.standard.object(forKey: "heartbeatMinutes") as? Int ?? 2 {
        didSet { UserDefaults.standard.set(heartbeatMinutes, forKey: "heartbeatMinutes") }
    }

    let vault = VaultController()
    @ObservationIgnored private(set) var sync: SyncController!
    @ObservationIgnored private(set) var recorder: PhoneRecorder!
    @ObservationIgnored private(set) var notes: PhoneNotes!
    @ObservationIgnored private(set) var meetings: MeetingController!

    @ObservationIgnored let coordinator = ModelCoordinator()
    private(set) var whisper: WhisperEngine
    var writing: SummaryEngine
    var modelState: TranscriptionModelState = .idle
    var writingModelState: TranscriptionModelState = .idle
    /// A first-time Core ML preparation in progress, for the status line.
    private(set) var preparation: ModelPreparation?
    private(set) var memoryPressure: MemoryPressureMonitor.Level = .normal
    @ObservationIgnored var applyingSync = false
    @ObservationIgnored private var modelTask: Task<Void, any Error>?
    @ObservationIgnored private var writingTask: Task<Void, Never>?
    @ObservationIgnored private var memoryMonitor: MemoryPressureMonitor?

    /// MLX needs a real GPU: the simulator can record and transcribe, but not run the writing model.
    static var canRunWritingModel: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    init() {
        let settings = Self.load(DictationSettings.self, key: Self.settingsKey) ?? DictationSettings()
        self.settings = settings
        let memory = Self.load(LanguageMemory.self, key: Self.languageMemoryKey) ?? LanguageMemory()
        self.languageMemory = memory
        self.styles = Self.loadStyles()
        self.writingSamples = Self.load([WritingSample].self, key: Self.samplesKey) ?? []
        self.whisper = WhisperEngine(variant: SpeechModels.bestVariant(for: memory.language(forApp: nil), settings: settings))
        self.writing = SummaryEngine(modelID: settings.writingModel)

        sync = SyncController(vault: vault)
        sync.localConfig = { [unowned self] base in localConfig(from: base) }
        sync.apply = { [unowned self] config in apply(config) }
        sync.retentionFolders = { [unowned self] in
            Array(Set(styles.map { notes.folder(for: $0) } + [NoteFiling.defaultFolder, StarterKit.samplesFolder]))
        }
        sync.expireRegularAudio = { [unowned self] in expireRegularAudio }
        sync.filedNotePaths = { [unowned self] in notes.recent.map(\.path) + (meetings?.sessions.compactMap(\.notePath) ?? []) }
        sync.filedNotesGone = { [unowned self] paths in
            notes.forget(paths)
            meetings?.forget(paths)
        }
        vault.onLocationReady = { [unowned self] in sync.syncSoon(after: .zero) }
        vault.onLayoutChanged = { [unowned self] in sync.layoutChanged() }
        recorder = PhoneRecorder(app: self)
        notes = PhoneNotes(app: self)
        meetings = MeetingController(app: self)
        // Lock Screen, Control Centre, Action Button, Siri: these can wake the app without a window.
        RecordingControl.handler = self
    }

    @ObservationIgnored private var bootstrapped = false

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
        #endif
        memoryMonitor = MemoryPressureMonitor { level in
            Task { @MainActor [weak self] in self?.memoryPressure = level }
        }
        sync.isHeld = !setupCompleted // nothing is written to storage until setup is done
        sync.start()
        if setupCompleted { prepareModel() }
    }

    func finishSetup() {
        setupCompleted = true
        sync.isHeld = false
        sync.syncSoon(after: .zero)
        if modelTask == nil { prepareModel() }
    }

    // MARK: Speech model

    /// Languages offered on this iPhone, always including the current one.
    var offeredLanguages: [SpokenLanguage] { settings.offeredLanguages(including: languageMemory.language(forApp: nil)) }

    var currentLanguage: SpokenLanguage { languageMemory.language(forApp: nil) }

    func useLanguage(_ language: SpokenLanguage) {
        languageMemory.remember(language, forApp: nil)
        let variant = SpeechModels.bestVariant(for: language, settings: settings)
        if whisper.variant != variant {
            let old = whisper
            whisper = WhisperEngine(variant: variant)
            modelState = .idle
            prepareModel(unloading: old)
        } else {
            let engine = whisper
            let vocabulary = settings.vocabulary(for: language)
            Task {
                await engine.setLanguage(language.code)
                await engine.setVocabulary(vocabulary)
            }
        }
    }

    /// Downloads (if needed), prepares and loads the current Whisper model.
    func prepareModel(unloading old: WhisperEngine? = nil) {
        guard meetings?.isProcessing != true else { return }
        let engine = whisper
        let language = currentLanguage
        let vocabulary = settings.vocabulary(for: language)
        modelTask = Task {
            if let old { await coordinator.unload(old) }
            await engine.setPreparationHandler { [weak self] preparation in
                Task { @MainActor in self?.preparation = preparation }
            }

            await engine.setLanguage(language.code)
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

    /// Starts loading the speech model if nothing has yet (a recording started before the app's window).
    func ensureModelLoading() {
        if modelTask == nil { prepareModel() }
    }

    /// Waits for the current model, following any switch made while waiting.
    func waitForModel() async throws {
        if modelTask == nil { prepareModel() }
        while let task = modelTask {
            try await task.value
            if task == modelTask { break }
        }
    }

    var speechModelName: String {
        TranscriptionModelOption.option(for: whisper.variant)?.name ?? whisper.variant
    }

    // MARK: Writing model (WritingHost)

    var writingModelOption: WritingModelOption? { WritingModelOption.option(for: settings.writingModel) }
    var writingModelDownloaded: Bool { Self.canRunWritingModel && writing.isDownloaded }

    func downloadWritingModel() {
        guard writingTask == nil, Self.canRunWritingModel else { return }
        let engine = writing
        writingModelState = .downloading(0)
        writingTask = Task {
            do {
                try await engine.download { fraction in
                    Task { @MainActor [weak self] in
                        if case .downloading = self?.writingModelState { self?.writingModelState = .downloading(fraction) }
                    }
                }
                if engine === writing { writingModelState = .idle }
            } catch {
                if engine === writing { writingModelState = .failed(error.localizedDescription) }
            }
            writingTask = nil
        }
    }

    func speechModelWillUnload() {
        modelState = .idle
    }

    func restoreWhisper() {
        writingModelState = .idle
        prepareModel()
    }

    // MARK: Settings

    private func settingsChanged(from old: DictationSettings) {
        save(settings, as: Self.settingsKey)
        if settings.writingModel != old.writingModel {
            let previous = writing
            writing = SummaryEngine(modelID: settings.writingModel)
            writingModelState = .idle
            Task { await coordinator.unload(previous) }
        }
        let language = currentLanguage
        if settings.transcriptionVariant(for: language) != old.transcriptionVariant(for: language)
            || settings.multilingualTranscriptionModel != old.multilingualTranscriptionModel {
            useLanguage(language)
        } else if settings.vocabulary(for: language) != old.vocabulary(for: language) {
            let engine = whisper
            let vocabulary = settings.vocabulary(for: language)
            Task { await engine.setVocabulary(vocabulary) }
        }
        if !applyingSync { sync?.syncSoon() }
    }

    // MARK: Styles

    static func loadStyles() -> [Style] {
        guard var saved = load([Style].self, key: stylesKey) else { return Style.presets }
        if !saved.contains(where: \.isRaw) { saved.insert(.raw, at: 0) }
        return saved
    }

    private func saveStyles(from old: [Style]) {
        save(styles, as: Self.stylesKey)
        if !applyingSync, styles != old { sync?.syncSoon() }
    }

    /// Styles offered after a recording, in their number order.
    var enabledStyles: [Style] {
        styles.filter(\.isEnabled).sorted { ($0.shortcut ?? 99) < ($1.shortcut ?? 99) }
    }

    var lastStyle: Style {
        enabledStyles.first { $0.id == lastStyleID } ?? enabledStyles.first { $0.id == Style.polished.id } ?? enabledStyles.first ?? .raw
    }

    // MARK: Vault settings file

    /// This iPhone's side of the settings file: shared styles, vocabulary, tags and samples, and its own
    /// device section (models, languages, sounds).
    func localConfig(from base: SharedConfig?) -> SharedConfig {
        var config = base ?? SharedConfig()
        config.styles = styles.map(ConfigStyle.init)
        config.vocabulary = settings.customVocabulary
        config.tags = tags
        config.taskKeywords = taskKeywords
        config.writingSamples = writingSamples
        config.expireRegularAudio = expireRegularAudio
        config.devices[sync.deviceName] = DeviceSection(settings)
        return config
    }

    func apply(_ config: SharedConfig) {
        applyingSync = true
        defer { applyingSync = false }
        var synced = config.styles.map(\.style)
        if !synced.contains(where: \.isRaw) { synced.insert(.raw, at: 0) }
        if synced != styles { styles = synced }
        var updated = settings
        updated.customVocabulary = config.vocabulary
        config.devices[sync.deviceName]?.apply(to: &updated)
        if updated != settings { settings = updated }
        if config.tags != tags { tags = config.tags }
        if config.taskKeywords != taskKeywords { taskKeywords = config.taskKeywords }
        if config.writingSamples != writingSamples { writingSamples = config.writingSamples }
        if config.expireRegularAudio != expireRegularAudio { expireRegularAudio = config.expireRegularAudio }
    }

    // MARK: Persistence

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, as key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}

extension PhoneModel: RecordingControlling {
    var isRecording: Bool { recorder.isRecording || meetings.ownsCapture }

    func startRecordingFromIntent() async throws {
        guard !meetings.ownsCapture, !meetings.isProcessing else {
            throw PhoneRecorder.RecordingError.couldNotStart(String(localized: "Finish the current meeting or processing job first."))
        }
        try await recorder.startRecordingFromIntent()
    }

    func pauseRecording() {
        if meetings.ownsCapture {
            if meetings.capture == .recording { Task { await meetings.togglePause() } }
        } else { recorder.pause() }
    }

    func resumeRecording() {
        if meetings.ownsCapture {
            if meetings.capture == .paused { Task { await meetings.togglePause() } }
        } else { recorder.resume() }
    }

    func stopRecordingFromIntent() async {
        if meetings.ownsCapture { await meetings.stop() }
        else { await recorder.stopRecordingFromIntent() }
    }
}
