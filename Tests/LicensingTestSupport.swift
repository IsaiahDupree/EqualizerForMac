import Foundation
@testable import SonanceEQ

/// Shared helpers for the licensing / payments / tracking / indicator suites.
///
/// Every factory uses a **unique** `UserDefaults` suite so parameterized cases never see each
/// other's state, and a **fixed clock** so timestamps are deterministic. Call `dispose(_:)` to
/// tear the suite down (cheap; safe to skip but keeps the test domain clean).
enum LicensingTestKit {
    /// A deterministic clock — all events land on the same instant unless a counter is supplied.
    static func fixedClock() -> () -> Date {
        { Date(timeIntervalSince1970: 1_700_000_000) }
    }

    /// A fresh tracker over an isolated defaults suite.
    @MainActor
    static func makeTracker(maxEvents: Int = 500) -> (tracker: PurchaseEventTracker, defaults: UserDefaults, suite: String) {
        let suite = "test.tracker.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (PurchaseEventTracker(defaults: defaults, maxEvents: maxEvents, clock: fixedClock()), defaults, suite)
    }

    /// A fresh, started `PurchaseManager` (mock store) over an isolated defaults suite.
    @MainActor
    static func makeManager() -> (manager: PurchaseManager, defaults: UserDefaults, suite: String) {
        let suite = "test.purchases.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let tracker = PurchaseEventTracker(defaults: defaults, clock: fixedClock())
        let manager = PurchaseManager(defaults: defaults, tracker: tracker)
        manager.start()
        return (manager, defaults, suite)
    }

    static func dispose(_ suite: String) {
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

/// Sample event details exercised by the persistence / Codable round-trip grids
/// (a `nil` plus realistic product-id and error strings).
let sampleDetails: [String?] = [
    nil,
    "com.isaiahdupree.SonanceEQ.pro",
    "The network connection was lost.",
    "Payment is not allowed on this device.",
    "Cannot connect to iTunes Store.",
    "This In-App Purchase has already been bought.",
    "Your purchase could not be completed.",
    "An unknown error occurred.",
    "Receipt is missing or invalid.",
    "Store problem — try again later.",
]

/// Natural (unlocked) SF Symbols used by the gated controls — exercised by the indicator grids.
let unlockedGlyphs: [String] = [
    "headphones", "slider.horizontal.3", "waveform.path",
    "circle.lefthalf.filled", "square.and.arrow.up.on.square",
    "record.circle", "slider.vertical.3",
]
