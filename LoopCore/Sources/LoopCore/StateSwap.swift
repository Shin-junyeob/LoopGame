import CAtomic

/// Main-thread owner of the render-state pointer. The render thread only touches `slot`:
/// load at callback start, epoch increment at callback end.
public final class StateSwap {
    public let slot: OpaquePointer
    private let free: (UnsafeMutableRawPointer) -> Void
    private var retired: [(state: UnsafeMutableRawPointer, epoch: UInt64)] = []

    public init(free: @escaping (UnsafeMutableRawPointer) -> Void) {
        slot = catomic_slot_create()
        self.free = free
    }

    /// Exchange first, then read epoch C; old state is freed once epoch >= C + 2.
    public func swap(to state: UnsafeMutableRawPointer?, engineRunning: Bool) {
        let old = catomic_exchange(slot, state)
        let c = catomic_epoch_load(slot)
        if !engineRunning {
            if let old { free(old) }
            retired.forEach { free($0.state) }
            retired = []
            return
        }
        if let old { retired.append((old, c)) }
        collect()
    }

    public func collect() {
        let now = catomic_epoch_load(slot)
        retired.removeAll { entry in
            guard now >= entry.epoch + 2 else { return false }
            free(entry.state)
            return true
        }
    }

    public var pendingCount: Int { retired.count }

    /// Assumes the engine is stopped.
    deinit {
        retired.forEach { free($0.state) }
        if let current = catomic_exchange(slot, nil) { free(current) }
        catomic_slot_destroy(slot)
    }
}
