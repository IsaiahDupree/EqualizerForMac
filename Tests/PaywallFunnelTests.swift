import Foundation
import Testing
@testable import SonanceEQ

/// Paywall impressions and end-to-end funnel invariants over many deterministic action sequences.
@MainActor
@Suite struct PaywallFunnelTests {

    // 1...25 = 25 — each paywallShown() is one impression; conversion = 1 / impressions after a buy.
    @Test(arguments: 1...25)
    func paywallShownRecordsImpression(_ impressions: Int) async {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        for _ in 0..<impressions { pm.paywallShown() }
        #expect(pm.tracker.count(of: .paywallShown) == impressions)
        await pm.purchasePro()
        #expect(pm.tracker.conversionRate == 1.0 / Double(impressions))
    }

    /// Map an index to a deterministic sequence of funnel actions (base-5 digits).
    private static func sequence(for index: Int) -> [Int] {
        guard index > 0 else { return [] }
        var n = index, digits: [Int] = []
        while n > 0 { digits.append(n % 5); n /= 5 }
        return digits
    }

    // 0...119 = 120 — apply a generated sequence, then assert the funnel accounting holds.
    @Test(arguments: 0...119)
    func funnelInvariantsHold(_ index: Int) async {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        let seq = Self.sequence(for: index)
        for step in seq {
            switch step {
            case 0: pm.paywallShown()
            case 1: pm.mockOutcome = .success;            await pm.purchasePro()
            case 2: pm.mockOutcome = .cancelled;          await pm.purchasePro()
            case 3: pm.mockOutcome = .failure("declined"); await pm.purchasePro()
            default: await pm.restore()
            }
        }
        let t = pm.tracker
        let started   = t.count(of: .purchaseStarted)
        let completed = t.count(of: .purchaseCompleted)
        let cancelled = t.count(of: .purchaseCancelled)
        let failed    = t.count(of: .purchaseFailed)
        // Every started purchase has exactly one terminal outcome.
        #expect(completed + cancelled + failed == started)
        #expect(completed <= started)
        // isPro iff at least one success occurred (no relock in this sequence).
        #expect(pm.isPro == (completed >= 1))
        // Restore accounting.
        let restoreStarted = t.count(of: .restoreStarted)
        #expect(t.count(of: .restoreCompleted) + t.count(of: .restoreNoEntitlement) == restoreStarted)
        // Impression count equals the number of paywallShown steps.
        #expect(t.count(of: .paywallShown) == seq.filter { $0 == 0 }.count)
        // Total log size equals the sum of all recorded event kinds.
        let total = PurchaseEvent.allCases.reduce(0) { $0 + t.count(of: $1) }
        #expect(total == t.events.count)
    }
}
