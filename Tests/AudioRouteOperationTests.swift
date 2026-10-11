import Foundation
import os
import Testing
@testable import SonanceEQ

/// Real serial queues, main-queue deadlines, semaphores and filesystem errors.
/// These test operation admission/cancellation, without substituting Core Audio.
@MainActor
@Suite(.serialized)
struct AudioRouteOperationTests {
    private func waitForWorkerReturn(_ semaphore: DispatchSemaphore) -> Bool {
        semaphore.wait(timeout: .now() + 1) == .success
    }
    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<250 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(4))
        }
        #expect(condition())
    }

    @Test func blockingWorkerLeavesMainQueueResponsiveAndRefusesOverlap() async {
        let operation = AudioRouteOperation<Bool>(label: "test.route.responsive")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let started = OSAllocatedUnfairLock(initialState: false)
        let cleanups = OSAllocatedUnfairLock(initialState: 0)
        var results: [Result<Bool, Error>] = []
        #expect(operation.run(work: { cancellation in
            started.withLock { $0 = true }
            release.wait()
            try cancellation.check()
            return Thread.isMainThread
        }, cleanup: { cleanups.withLock { $0 += 1 } }, outcome: { results.append($0) }))
        await waitFor { started.withLock { $0 } }
        var mainTimerFired = false
        DispatchQueue.main.async { mainTimerFired = true }
        await waitFor { mainTimerFired }
        #expect(operation.inFlight)
        #expect(results.isEmpty)
        #expect(!operation.run(work: { _ in true }, cleanup: {}, outcome: { _ in
            Issue.record("An overlapping route was admitted")
        }))
        release.signal()
        await waitFor { !operation.inFlight }
        #expect(results.count == 1)
        if case let .success(onMain) = results.first { #expect(!onMain) }
        else { Issue.record("Worker should complete successfully") }
        #expect(cleanups.withLock { $0 } == 0)
    }

    @Test func stopWithholdsLateSuccessUntilWorkerCleanupCompletes() async {
        let operation = AudioRouteOperation<Int>(label: "test.route.cancel")
        let release = DispatchSemaphore(value: 0)
        let releaseCleanup = DispatchSemaphore(value: 0)
        defer { release.signal(); releaseCleanup.signal() }
        let started = OSAllocatedUnfairLock(initialState: false)
        let cleaning = OSAllocatedUnfairLock(initialState: false)
        var results: [Result<Int, Error>] = []
        operation.run(work: { _ in
            started.withLock { $0 = true }
            release.wait()
            return 1
        }, cleanup: {
            cleaning.withLock { $0 = true }
            releaseCleanup.wait()
        }, outcome: { results.append($0) })
        await waitFor { started.withLock { $0 } }
        operation.cancel()
        #expect(results.count == 1)
        if case let .failure(error) = results.first { #expect(error is CancellationError) }
        else { Issue.record("Stop should cancel the pending outcome") }
        #expect(operation.inFlight)
        release.signal()
        await waitFor { cleaning.withLock { $0 } }
        #expect(operation.inFlight)
        #expect(!operation.run(work: { _ in 2 }, cleanup: {}, outcome: { _ in }))
        releaseCleanup.signal()
        await waitFor { !operation.inFlight }
        #expect(results.count == 1)
        #expect(operation.run(work: { _ in 3 }, cleanup: {}, outcome: { results.append($0) }))
        await waitFor { !operation.inFlight }
        #expect(results.count == 2)
        if case let .success(value) = results.last { #expect(value == 3) }
        else { Issue.record("A fresh operation should work after cleanup") }
    }

    @Test func timeoutIsOneFailureAndDoesNotFreeAnUnfinishedSlot() async {
        let operation = AudioRouteOperation<Int>(label: "test.route.timeout")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let cleanups = OSAllocatedUnfairLock(initialState: 0)
        var results: [Result<Int, Error>] = []
        operation.run(timeout: 0.05, work: { _ in release.wait(); return 1 },
                      cleanup: { cleanups.withLock { $0 += 1 } },
                      outcome: { results.append($0) })
        await waitFor { results.count == 1 }
        if case let .failure(error) = results.first {
            #expect(error is AudioRouteOperation<Int>.Failure)
        } else { Issue.record("Expected the real main-queue deadline") }
        #expect(operation.inFlight)
        operation.cancel()
        #expect(results.count == 1)
        release.signal()
        await waitFor { !operation.inFlight }
        #expect(results.count == 1)
        #expect(cleanups.withLock { $0 } == 1)
    }

    @Test func cancellationAfterWorkerReturnStillCleansBeforeCompletion() async {
        let operation = AudioRouteOperation<Int>(label: "test.route.completion-race")
        let returned = DispatchSemaphore(value: 0)
        let cleanups = OSAllocatedUnfairLock(initialState: 0)
        var results: [Result<Int, Error>] = []
        operation.run(work: { _ in returned.signal(); return 1 },
                      cleanup: { cleanups.withLock { $0 += 1 } },
                      outcome: { results.append($0) })
        // Hold the main actor until the real worker returns, then cancel before
        // its main-queue completion can run. This is the late-completion race.
        #expect(waitForWorkerReturn(returned))
        operation.queue.sync {} // its completion is now waiting on the held main actor
        operation.cancel()
        await waitFor { !operation.inFlight }
        #expect(results.count == 1)
        #expect(cleanups.withLock { $0 } == 1)
        if case let .failure(error) = results.first { #expect(error is CancellationError) }
        else { Issue.record("Late completion must remain cancelled") }
    }

    @Test func actualFilesystemFailureCleansAndPreservesItsError() async {
        let operation = AudioRouteOperation<Data>(label: "test.route.file-error")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cleanups = OSAllocatedUnfairLock(initialState: 0)
        var results: [Result<Data, Error>] = []
        operation.run(work: { _ in try Data(contentsOf: root.appendingPathComponent("absent")) },
                      cleanup: { cleanups.withLock { $0 += 1 } },
                      outcome: { results.append($0) })
        await waitFor { !operation.inFlight }
        #expect(results.count == 1)
        #expect(cleanups.withLock { $0 } == 1)
        if case let .failure(error) = results.first {
            #expect((error as NSError).domain == NSCocoaErrorDomain)
        } else { Issue.record("Expected the real missing-file error") }
    }

    @Test func oldDeadlineCannotFailTheNextOperation() async {
        let operation = AudioRouteOperation<Int>(label: "test.route.old-deadline")
        var results: [Result<Int, Error>] = []
        operation.run(timeout: 0.05, work: { _ in 1 }, cleanup: {}, outcome: { results.append($0) })
        await waitFor { !operation.inFlight }
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        operation.run(timeout: 1, work: { _ in release.wait(); return 2 },
                      cleanup: {}, outcome: { results.append($0) })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(operation.inFlight)
        #expect(results.count == 1)
        release.signal()
        await waitFor { !operation.inFlight }
        #expect(results.count == 2)
        if case let .success(value) = results.last { #expect(value == 2) }
        else { Issue.record("An earlier deadline affected a fresh operation") }
    }
}
