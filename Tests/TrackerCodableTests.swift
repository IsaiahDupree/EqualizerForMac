import Foundation
import Testing
@testable import SonanceEQ

/// One (event, store, detail) combination for the Codable grid — a single Sendable argument so the
/// case set is a flat collection (Swift Testing has no 3-collection `arguments:` overload).
struct CodableCase: Sendable {
    let event: PurchaseEvent
    let store: String
    let detail: String?
}

/// The full 9 × 2 × 10 = 180 combination grid.
let codableCases: [CodableCase] = PurchaseEvent.allCases.flatMap { event in
    ["mock", "revenueCat"].flatMap { store in
        sampleDetails.map { CodableCase(event: event, store: store, detail: $0) }
    }
}

/// `TrackedEvent` / event-log Codable round-trips — the persistence contract the tracker relies on.
@MainActor
@Suite struct TrackerCodableTests {
    // 9 events × 2 stores × 10 details = 180 cases — a single event round-trips through JSON.
    @Test(arguments: codableCases)
    func trackedEventRoundTrips(_ c: CodableCase) throws {
        let original = TrackedEvent(event: c.event, store: c.store, detail: c.detail,
                                    date: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrackedEvent.self, from: data)
        #expect(decoded == original)
        #expect(decoded.event == c.event)
        #expect(decoded.store == c.store)
        #expect(decoded.detail == c.detail)
    }

    // 0...30 = 31 cases — a whole log array round-trips through UserDefaults.
    @Test(arguments: 0...30)
    func eventLogRoundTripsThroughDefaults(_ n: Int) {
        let (tracker, defaults, suite) = LicensingTestKit.makeTracker()
        defer { LicensingTestKit.dispose(suite) }
        let all = PurchaseEvent.allCases
        for i in 0..<n {
            tracker.record(all[i % all.count], store: i.isMultiple(of: 2) ? "mock" : "revenueCat",
                           detail: "d\(i)")
        }
        let original = tracker.events
        let reloaded = PurchaseEventTracker(defaults: defaults, clock: LicensingTestKit.fixedClock())
        #expect(reloaded.events == original)
        #expect(reloaded.events.count == n)
    }

    @Test func everyEventRawValueIsStableAndUnique() {
        // Codable uses rawValue keys — they must be unique and not silently renamed.
        let raws = PurchaseEvent.allCases.map(\.rawValue)
        #expect(Set(raws).count == raws.count)
        #expect(PurchaseEvent(rawValue: "paywallShown") == .paywallShown)
        #expect(PurchaseEvent(rawValue: "definitely-not-an-event") == nil)
    }

    @Test func corruptStoredDataDecaysToEmptyLog() {
        // A garbage blob under the storage key must not crash — it loads as an empty log.
        let suite = "test.corrupt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { LicensingTestKit.dispose(suite) }
        defaults.set(Data([0x00, 0x01, 0x02, 0xFF]), forKey: PurchaseEventTracker.storageKey)
        let tracker = PurchaseEventTracker(defaults: defaults, clock: LicensingTestKit.fixedClock())
        #expect(tracker.events.isEmpty)
        // …and it can still record normally afterwards.
        tracker.record(.paywallShown, store: "mock")
        #expect(tracker.events.count == 1)
    }
}
