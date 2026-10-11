import Foundation
import os

/// Runs one blocking route operation off the main thread. Cancellation changes intent;
/// it cannot interrupt a Core Audio IPC. The slot stays occupied until that call returns
/// and its cleanup finishes, so a timeout never admits a second overlapping route.
@MainActor
final class AudioRouteOperation<Value> {
    final class Cancellation: Sendable {
        private let cancelled = OSAllocatedUnfairLock(initialState: false)
        var isCancelled: Bool { cancelled.withLock { $0 } }
        func cancel() { cancelled.withLock { $0 = true } }
        func check() throws { if isCancelled { throw CancellationError() } }
    }

    enum Failure: Error { case timedOut }

    let queue: DispatchQueue
    private(set) var inFlight = false
    private var token: Cancellation?
    private var deadline: DispatchWorkItem?
    private var outcome: ((Result<Value, Error>) -> Void)?
    private var finished: (() -> Void)?

    init(label: String) { queue = DispatchQueue(label: label, qos: .userInitiated) }

    @discardableResult
    func run(timeout: TimeInterval = 10,
             work: @escaping (Cancellation) throws -> Value,
             cleanup: @escaping () -> Void,
             outcome: @escaping (Result<Value, Error>) -> Void,
             finished: @escaping () -> Void = {}) -> Bool {
        precondition(timeout.isFinite && timeout > 0)
        guard !inFlight else { return false }
        inFlight = true
        let token = Cancellation()
        self.token = token
        self.outcome = outcome
        self.finished = finished
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.token === token else { return }
            token.cancel()
            self.deliver(.failure(Failure.timedOut))
        }
        self.deadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: deadline)
        queue.async {
            var cleaned = false
            let result: Result<Value, Error>
            do {
                try token.check()
                let value = try work(token)
                try token.check()
                result = .success(value)
            } catch {
                cleanup()
                cleaned = true
                result = .failure(error)
            }
            let cleanupDone = cleaned
            DispatchQueue.main.async {
                guard self.token === token else { return }
                // Stop may have arrived after the worker's final cancellation check,
                // while this completion was waiting on the main queue.
                if token.isCancelled && !cleanupDone {
                    self.queue.async {
                        cleanup()
                        DispatchQueue.main.async { self.complete(token, .failure(CancellationError())) }
                    }
                } else {
                    self.complete(token, result)
                }
            }
        }
        return true
    }

    func cancel() {
        guard let token else { return }
        token.cancel()
        deadline?.cancel()
        deliver(.failure(CancellationError()))
    }

    private func deliver(_ result: Result<Value, Error>) {
        let callback = outcome
        outcome = nil
        callback?(result)
    }

    private func complete(_ expected: Cancellation, _ result: Result<Value, Error>) {
        guard token === expected else { return }
        deadline?.cancel()
        deadline = nil
        token = nil
        inFlight = false
        let callback = finished
        finished = nil
        deliver(result)
        callback?()
    }
}
