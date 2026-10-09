import Foundation
import os

/// Checks one route's audio callbacks on the control plane. Each build owns a new heartbeat, so
/// callbacks or queued timeouts from a previous route cannot make a replacement route look healthy.
/// Lifecycle methods run on the main queue; only Heartbeat.recordRender() runs on the audio queue.
final class AudioRouteWatchdog {
    enum State { case stopped, waiting, flowing, failed }

    final class Heartbeat {
        private let count = OSAllocatedUnfairLock(initialState: 0)
        var deliveredBlocks: Int { count.withLock { $0 } }
        func recordRender() { count.withLock { $0 &+= 1 } }
    }

    private let timeout: TimeInterval
    private var generation: UInt64 = 0
    private var pending: DispatchWorkItem?
    private(set) var heartbeat: Heartbeat?
    private(set) var state: State = .stopped

    init(timeout: TimeInterval = 1.5) {
        precondition(timeout.isFinite && timeout > 0)
        self.timeout = timeout
    }

    /// Called before creating/starting the IOProc, preserving even its first delivered callback.
    @discardableResult
    func beginRoute() -> Heartbeat {
        invalidatePending()
        let heartbeat = Heartbeat()
        self.heartbeat = heartbeat
        state = .waiting
        return heartbeat
    }

    func arm(_ completion: @escaping (Bool) -> Void) {
        guard state == .waiting, let heartbeat else { return }
        pending?.cancel()
        // Cancellation alone cannot retract work already queued for execution. Every arm has a
        // distinct token, including a second arm of the same route.
        generation &+= 1
        let expectedGeneration = generation
        let item = DispatchWorkItem { [weak self, weak heartbeat] in
            guard let self, let heartbeat, self.generation == expectedGeneration,
                  self.heartbeat === heartbeat, self.state == .waiting else { return }
            self.pending = nil
            let flowing = heartbeat.deliveredBlocks > 0
            self.state = flowing ? .flowing : .failed
            completion(flowing)
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: item)
    }

    func stop() {
        invalidatePending()
        heartbeat = nil
        state = .stopped
    }

    private func invalidatePending() {
        generation &+= 1
        pending?.cancel()
        pending = nil
    }

    deinit { pending?.cancel() }
}
