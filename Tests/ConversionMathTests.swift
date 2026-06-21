import Foundation
import Testing
@testable import SonanceEQ

/// Funnel arithmetic across the full small-integer input space, including the div-by-zero guards.
/// Each grid is 16 × 16 = 256 cases.
@MainActor
@Suite struct ConversionMathTests {

    @Test(arguments: 0...15, 0...15)
    func conversionRateGrid(_ shown: Int, _ completed: Int) {
        let (tracker, _, suite) = LicensingTestKit.makeTracker()
        defer { LicensingTestKit.dispose(suite) }
        for _ in 0..<shown { tracker.record(.paywallShown, store: "mock") }
        for _ in 0..<completed { tracker.record(.purchaseCompleted, store: "mock") }
        if shown == 0 {
            #expect(tracker.conversionRate == nil)
        } else {
            #expect(tracker.conversionRate == Double(completed) / Double(shown))
        }
    }

    @Test(arguments: 0...15, 0...15)
    func restoreSuccessRateGrid(_ started: Int, _ completed: Int) {
        let (tracker, _, suite) = LicensingTestKit.makeTracker()
        defer { LicensingTestKit.dispose(suite) }
        for _ in 0..<started { tracker.record(.restoreStarted, store: "mock") }
        for _ in 0..<completed { tracker.record(.restoreCompleted, store: "mock") }
        if started == 0 {
            #expect(tracker.restoreSuccessRate == nil)
        } else {
            #expect(tracker.restoreSuccessRate == Double(completed) / Double(started))
        }
    }

    @Test(arguments: 0...15, 0...15)
    func purchaseFailureRateGrid(_ started: Int, _ failed: Int) {
        let (tracker, _, suite) = LicensingTestKit.makeTracker()
        defer { LicensingTestKit.dispose(suite) }
        for _ in 0..<started { tracker.record(.purchaseStarted, store: "mock") }
        for _ in 0..<failed { tracker.record(.purchaseFailed, store: "mock") }
        if started == 0 {
            #expect(tracker.purchaseFailureRate == nil)
        } else {
            #expect(tracker.purchaseFailureRate == Double(failed) / Double(started))
        }
    }
}
