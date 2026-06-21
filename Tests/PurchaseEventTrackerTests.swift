import Foundation
import Testing
@testable import SonanceEQ

/// Core behaviour of `PurchaseEventTracker`: recording, counting, persistence, ring-buffer cap,
/// and the division-by-zero guards on the rate properties.
@MainActor
@Suite struct PurchaseEventTrackerTests {
    private let stores = ["mock", "revenueCat"]

    // 9 events × 2 stores = 18 cases.
    @Test(arguments: PurchaseEvent.allCases, ["mock", "revenueCat"])
    func recordsEventOnStore(_ event: PurchaseEvent, _ store: String) {
        let (tracker, _, suite) = LicensingTestKit.makeTracker()
        defer { LicensingTestKit.dispose(suite) }
        let entry = tracker.record(event, store: store)
        #expect(tracker.events.count == 1)
        #expect(tracker.lastEvent == entry)
        #expect(tracker.lastEvent?.event == event)
        #expect(tracker.lastEvent?.store == store)
        #expect(tracker.count(of: event) == 1)
    }

    // 9 events × 10 details = 90 cases — the detail survives a persist + reload.
    @Test(arguments: PurchaseEvent.allCases, sampleDetails)
    func persistsAndReloadsDetail(_ event: PurchaseEvent, _ detail: String?) {
        let (tracker, defaults, suite) = LicensingTestKit.makeTracker()
        defer { LicensingTestKit.dispose(suite) }
        tracker.record(event, store: "mock", detail: detail)
        // A brand-new tracker over the same defaults must see the persisted event verbatim.
        let reloaded = PurchaseEventTracker(defaults: defaults, clock: LicensingTestKit.fixedClock())
        #expect(reloaded.events.count == 1)
        #expect(reloaded.lastEvent?.event == event)
        #expect(reloaded.lastEvent?.detail == detail)
    }

    // 0...40 = 41 cases — count() equals the number recorded.
    @Test(arguments: 0...40)
    func countMatchesNumberRecorded(_ n: Int) {
        let (tracker, _, suite) = LicensingTestKit.makeTracker()
        defer { LicensingTestKit.dispose(suite) }
        for _ in 0..<n { tracker.record(.paywallShown, store: "mock") }
        #expect(tracker.count(of: .paywallShown) == n)
        #expect(tracker.events.count == n)
        #expect(tracker.events(of: .paywallShown).count == n)
        #expect(tracker.count(of: .purchaseCompleted) == 0)
    }

    // 1...30 = 30 cases — ring buffer keeps only the newest `max`, dropping the oldest.
    @Test(arguments: 1...30)
    func ringBufferCapsAtMax(_ max: Int) {
        let (tracker, _, suite) = LicensingTestKit.makeTracker(maxEvents: max)
        defer { LicensingTestKit.dispose(suite) }
        let overshoot = max + 5
        // Tag each event by detail so we can prove the *oldest* rolled off.
        for i in 0..<overshoot { tracker.record(.purchaseStarted, store: "mock", detail: "\(i)") }
        #expect(tracker.events.count == max)
        #expect(tracker.lastEvent?.detail == "\(overshoot - 1)")          // newest kept
        #expect(tracker.events.first?.detail == "\(overshoot - max)")     // oldest survivor
    }

    // 0...20 = 21 cases — clear empties memory and persistence.
    @Test(arguments: 0...20)
    func clearEmptiesEverything(_ n: Int) {
        let (tracker, defaults, suite) = LicensingTestKit.makeTracker()
        defer { LicensingTestKit.dispose(suite) }
        for _ in 0..<n { tracker.record(.restoreStarted, store: "mock") }
        tracker.clear()
        #expect(tracker.events.isEmpty)
        #expect(tracker.lastEvent == nil)
        let reloaded = PurchaseEventTracker(defaults: defaults, clock: LicensingTestKit.fixedClock())
        #expect(reloaded.events.isEmpty)
    }

    // 1...25 = 25 cases — lastEvent is always the most recently recorded.
    @Test(arguments: 1...25)
    func lastEventIsMostRecent(_ n: Int) {
        let (tracker, _, suite) = LicensingTestKit.makeTracker()
        defer { LicensingTestKit.dispose(suite) }
        let all = PurchaseEvent.allCases
        var expected: PurchaseEvent = .paywallShown
        for i in 0..<n {
            expected = all[i % all.count]
            tracker.record(expected, store: "mock")
        }
        #expect(tracker.lastEvent?.event == expected)
        #expect(tracker.events.count == n)
    }

    @Test func conversionRateNilWithNoPaywall() {
        let (tracker, _, suite) = LicensingTestKit.makeTracker()
        defer { LicensingTestKit.dispose(suite) }
        #expect(tracker.conversionRate == nil)
        tracker.record(.purchaseCompleted, store: "mock")   // a completion with no impression
        #expect(tracker.conversionRate == nil)              // still nil — "no impressions" ≠ "0%"
    }

    @Test func failureAndRestoreRatesNilUntilStarted() {
        let (tracker, _, suite) = LicensingTestKit.makeTracker()
        defer { LicensingTestKit.dispose(suite) }
        #expect(tracker.purchaseFailureRate == nil)
        #expect(tracker.restoreSuccessRate == nil)
    }

    @Test func emptyTrackerHasNoLastEvent() {
        let (tracker, _, suite) = LicensingTestKit.makeTracker()
        defer { LicensingTestKit.dispose(suite) }
        #expect(tracker.events.isEmpty)
        #expect(tracker.lastEvent == nil)
        for e in PurchaseEvent.allCases { #expect(tracker.count(of: e) == 0) }
    }
}
