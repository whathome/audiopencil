import APCore
import Foundation

public enum ModelKind: String, Sendable {
    case transcription
    case summarization
}

/// A large on-device model whose residency is controlled by `ModelCoordinator`.
public protocol ManagedModel: AnyObject, Sendable {
    nonisolated var kind: ModelKind { get }
    nonisolated var displayName: String { get }
    /// Loads weights into memory. Called only by the coordinator.
    func load() async throws
    /// Frees weights and any cached GPU/ANE buffers. Called only by the coordinator.
    func unload() async
}

/// Enforces the 8 GB rule: at most one large model is resident at a time.
///
/// Every load goes through `ensureLoaded`, which unloads whatever else is resident first.
/// Loads and unloads are serialised so two callers can never overlap a swap.
public actor ModelCoordinator {
    private let lock = AsyncLock()
    private var resident: (any ManagedModel)?

    public init() {}

    public var residentModelName: String? { resident?.displayName }

    public func isResident(_ model: any ManagedModel) -> Bool {
        resident === model
    }

    /// Makes `model` the only resident model, unloading any other first.
    public func ensureLoaded(_ model: any ManagedModel) async throws {
        await lock.acquire()
        do {
            try await swap(to: model)
            await lock.release()
        } catch {
            await lock.release()
            throw error
        }
    }

    /// Unloads `model` if it is the resident one.
    public func unload(_ model: any ManagedModel) async {
        await lock.acquire()
        if resident === model {
            await model.unload()
            resident = nil
            Log.models.info("Unloaded \(model.displayName, privacy: .public)")
        }
        await lock.release()
    }

    private func swap(to model: any ManagedModel) async throws {
        if resident === model { return }
        if let current = resident {
            Log.models.notice("Unloading \(current.displayName, privacy: .public) before loading \(model.displayName, privacy: .public)")
            await current.unload()
            resident = nil
        }
        let start = ContinuousClock.now
        try await model.load()
        resident = model
        let elapsed = ContinuousClock.now - start
        Log.models.notice("Loaded \(model.displayName, privacy: .public) in \(elapsed, privacy: .public); footprint \(MemoryFootprint.formatted(MemoryFootprint.currentBytes()), privacy: .public)")
    }
}
