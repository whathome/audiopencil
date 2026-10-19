import APCore
import Dispatch

/// Reports system memory-pressure transitions. Milestone 1 only logs them; milestone 3 uses
/// them to defer or refuse an LLM load.
public final class MemoryPressureMonitor: Sendable {
    public enum Level: String, Sendable {
        case normal, warning, critical
    }

    private let source: any DispatchSourceMemoryPressure

    public init(onChange: @escaping @Sendable (Level) -> Void) {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [source] in
            let event = source.data
            let level: Level = event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal
            Log.models.notice("Memory pressure: \(level.rawValue, privacy: .public); footprint \(MemoryFootprint.formatted(MemoryFootprint.currentBytes()), privacy: .public)")
            onChange(level)
        }
        source.activate()
    }

    deinit {
        source.cancel()
    }
}
