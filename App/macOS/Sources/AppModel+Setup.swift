import APCore
import APModels
import APTranscription
import AppKit
import SwiftUI

/// A model setup downloads and prepares, for the "Your models" and "Getting ready" steps.
struct SetupModel: Identifiable, Equatable {
    enum Kind: Equatable {
        case whisper(String)
        case writing
    }

    let kind: Kind
    let name: String
    let purpose: String
    let downloadMB: Int
    /// Already on this Mac: nothing to download.
    let downloaded: Bool
    /// First-time preparation for this Mac, in seconds (writing models need none).
    let prepareSeconds: Double?

    var id: String {
        switch kind {
        case .whisper(let variant): variant
        case .writing: "writing"
        }
    }
}

enum SetupModelStatus: Equatable {
    case waiting
    case downloading(Double)
    case preparing(ModelPreparation?)
    case ready
    case failed(String)
}

/// The guided setup window: first launch, or Settings › Run Setup Again.
extension AppModel {
    static let setupCompletedKey = "setupCompleted"

    /// True on a Mac that has never run the app. Existing installs (settings, stats, storage or styles
    /// already saved) count as set up, and are marked so.
    static func checkFirstLaunch() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: setupCompletedKey) { return false }
        let earlierInstall = [settingsKey, statsKey, stylesKey, "vaultSettings"].contains { defaults.object(forKey: $0) != nil }
        if earlierInstall { defaults.set(true, forKey: setupCompletedKey) }
        return !earlierInstall
    }

    func showSetup(hidingMainWindow: Bool) {
        if setupWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = String(localized: "Set Up Audio Pencil")
            window.identifier = NSUserInterfaceItemIdentifier("setup")
            setupWindow = window
            // Closing the window at any step ends setup: what was chosen so far stands.
            setupCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishSetup(showingMainWindow: true) }
            }
        }
        setupStep = .welcome
        setupWindow?.contentView = NSHostingView(rootView: SetupFlow(app: self) { [weak self] in self?.setupWindow?.close() })
        setupWindow?.center()
        NSApp.activate()
        setupWindow?.makeKeyAndOrderFront(nil)
        if hidingMainWindow {
            // SwiftUI opens the main window at launch; hide it (not close, so it can come back).
            DispatchQueue.main.async { Self.mainWindow?.orderOut(nil) }
        }
    }

    /// Setup is done (or closed early): remember it, let storage sync, and make sure the model loads.
    func finishSetup(showingMainWindow: Bool) {
        UserDefaults.standard.set(true, forKey: Self.setupCompletedKey)
        if sync.isHeld {
            sync.isHeld = false
            sync.syncSoon(after: .zero)
        }
        if modelTask == nil { prepareModel() }
        if showingMainWindow {
            Self.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }

    /// The Permissions step: start on the model dictation will use while the user grants access.
    func startSetupModel() {
        if modelTask == nil { prepareModel() }
    }

    /// "Getting ready": the writing model joins the background work if the user wants styles.
    func startSetupDownloads(writing: Bool) {
        if writing, !writingModelDownloaded { downloadWritingModel() }
        finishSetup(showingMainWindow: false)
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" }
    }

    // MARK: Models

    /// What dictation in the chosen languages needs on this Mac, in the order it's prepared.
    func setupModels(includingWriting: Bool) -> [SetupModel] {
        var models: [SetupModel] = []
        func whisper(_ variant: String, purpose: String) {
            guard !models.contains(where: { $0.kind == .whisper(variant) }) else { return }
            let option = TranscriptionModelOption.option(for: variant)
            let engine = WhisperEngine(variant: variant)
            models.append(SetupModel(
                kind: .whisper(variant),
                name: "Whisper " + (option?.name ?? variant),
                purpose: purpose,
                downloadMB: option?.approximateDownloadMB ?? 500,
                downloaded: engine.isDownloaded,
                prepareSeconds: engine.isReady ? nil
                    : PreparationEstimate.seconds(variant: variant, folder: ModelLocations.whisperFolder(variant: variant))
            ))
        }
        let languages = offeredLanguages
        if languages.contains(where: \.isEnglish) {
            whisper(settings.transcriptionModel, purpose: String(localized: "English dictation"))
        }
        if languages.contains(where: { !$0.isEnglish }) {
            let target = Self.multilingualTarget(settings)
            if target == Self.starterMultilingualModel {
                whisper(target, purpose: String(localized: "Your other languages"))
            } else {
                whisper(Self.starterMultilingualModel, purpose: String(localized: "Your other languages, straight away"))
                whisper(target, purpose: String(localized: "More accurate in your other languages; takes over once it's ready"))
            }
        }
        if includingWriting, let option = writingModelOption {
            models.append(SetupModel(
                kind: .writing,
                name: option.name,
                purpose: String(localized: "Writes your styles and long-form notes"),
                downloadMB: Int(option.approximateDownloadGB * 1000),
                downloaded: writingModelDownloaded,
                prepareSeconds: nil
            ))
        }
        return models
    }

    func setupStatus(of model: SetupModel) -> SetupModelStatus {
        switch model.kind {
        case .writing:
            switch writingModelState {
            case .downloading(let fraction): return .downloading(fraction)
            case .failed(let message): return .failed(message)
            default: return writingModelDownloaded ? .ready : (writingTask != nil ? .downloading(0) : .waiting)
            }
        case .whisper(let variant):
            if variant == whisper.variant {
                switch modelState {
                case .downloading(let fraction): return .downloading(fraction)
                case .loading: return .preparing(preparation?.variant == variant ? preparation : nil)
                case .ready: return .ready
                case .failed(let message): return .failed(message)
                case .idle: break
                }
            }
            if multilingualDownloadVariant == variant {
                if let fraction = multilingualDownload { return .downloading(fraction) }
                return .preparing(preparation?.variant == variant ? preparation : nil)
            }
            return WhisperEngine(variant: variant).isReady ? .ready : .waiting
        }
    }
}
