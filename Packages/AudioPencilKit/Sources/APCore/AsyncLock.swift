/// A FIFO mutual-exclusion lock for async code. Unlike actor isolation, it stays held across
/// suspension points, so a whole load/unload sequence runs without interleaving.
public actor AsyncLock {
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func acquire() async {
        if !held {
            held = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    public func release() {
        if waiters.isEmpty {
            held = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

extension AsyncLock {
    /// Runs `body` while holding the lock. Runs on the caller's actor.
    public nonisolated func withLock<T>(_ body: () async throws -> T) async throws -> T {
        await acquire()
        do {
            let result = try await body()
            await release()
            return result
        } catch {
            await release()
            throw error
        }
    }
}
