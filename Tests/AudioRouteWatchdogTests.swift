import Foundation
import Testing
@testable import SonanceEQ

/// Exercises the shipping heartbeat and real main-queue timers. No Core Audio/provider replacement
/// is installed here: these tests prove lifecycle isolation, not that a physical output is audible.
@MainActor
@Suite(.serialized) struct AudioRouteWatchdogTests {
    private func wait(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    @Test func waitingRouteDoesNotInheritPreviousCallbacks() {
        let watchdog = AudioRouteWatchdog()
        let first = watchdog.beginRoute()
        first.recordRender()
        let replacement = watchdog.beginRoute()
        first.recordRender()   // a callback that was already in flight during teardown
        #expect(watchdog.state == .waiting)
        #expect(replacement.deliveredBlocks == 0)
        #expect(first.deliveredBlocks == 2)
        watchdog.stop()
        #expect(watchdog.state == .stopped)
        #expect(watchdog.heartbeat == nil)
    }

    @Test func callbackBeforeWatchdogArmIsPreserved() async throws {
        let watchdog = AudioRouteWatchdog(timeout: 0.05)
        let heartbeat = watchdog.beginRoute()
        heartbeat.recordRender()   // AudioDeviceStart can call the IOProc before build() returns
        var results: [Bool] = []
        watchdog.arm { results.append($0) }
        try await wait(0.15)
        #expect(results == [true])
        #expect(watchdog.state == .flowing)
        #expect(heartbeat.deliveredBlocks == 1)
    }

    @Test func oldCallbacksCannotPreventReplacementFailure() async throws {
        let watchdog = AudioRouteWatchdog(timeout: 0.05)
        let first = watchdog.beginRoute()
        first.recordRender()
        watchdog.beginRoute()
        var results: [Bool] = []
        watchdog.arm { results.append($0) }
        first.recordRender()
        try await wait(0.15)
        #expect(results == [false])
        #expect(watchdog.state == .failed)
        try await wait(0.1)
        #expect(results == [false])   // failure is delivered once
    }

    @Test func replacementGetsItsOwnFullDeadline() async throws {
        let watchdog = AudioRouteWatchdog(timeout: 1.2)
        watchdog.beginRoute()
        var results: [Bool] = []
        watchdog.arm { results.append($0) }
        try await wait(0.8)
        let replacement = watchdog.beginRoute()
        watchdog.arm { results.append($0) }
        try await wait(0.6)   // old deadline passed; replacement still has ample time to render
        #expect(results.isEmpty)
        #expect(watchdog.state == .waiting)
        replacement.recordRender()
        try await wait(0.9)
        #expect(results == [true])
        #expect(watchdog.state == .flowing)
    }

    @Test func stoppedRouteCannotReportFailureLater() async throws {
        let watchdog = AudioRouteWatchdog(timeout: 0.05)
        watchdog.beginRoute()
        var results: [Bool] = []
        watchdog.arm { results.append($0) }
        watchdog.stop()
        try await wait(0.15)
        #expect(results.isEmpty)
        #expect(watchdog.state == .stopped)
    }

    @Test func stopThenRestartCannotReuseHeartbeatOrDeadline() async throws {
        let watchdog = AudioRouteWatchdog(timeout: 1.2)
        let first = watchdog.beginRoute()
        var results: [Bool] = []
        watchdog.arm { results.append($0) }
        try await wait(0.8)
        watchdog.stop()
        let replacement = watchdog.beginRoute()
        watchdog.arm { results.append($0) }
        first.recordRender()
        try await wait(0.6)
        #expect(results.isEmpty)
        #expect(replacement.deliveredBlocks == 0)
        #expect(watchdog.state == .waiting)
        try await wait(0.9)
        #expect(results == [false])
        #expect(watchdog.state == .failed)
    }

    @Test func rearmingSameRouteInvalidatesEarlierTimer() async throws {
        let watchdog = AudioRouteWatchdog(timeout: 1.2)
        watchdog.beginRoute()
        var results: [Bool] = []
        watchdog.arm { results.append($0) }
        try await wait(0.8)
        watchdog.arm { results.append($0) }
        try await wait(0.6)
        #expect(results.isEmpty)
        #expect(watchdog.state == .waiting)
        try await wait(0.9)
        #expect(results == [false])
    }
}
