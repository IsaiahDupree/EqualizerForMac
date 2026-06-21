import Foundation
import Testing
@testable import SonanceEQ

/// Payment outcomes on the mock store: success, user-cancel, and failure — each drives `isPro`,
/// `lastError`, and the tracked funnel events. This is how the cancel/failure code paths get
/// exercised without StoreKit.
@MainActor
@Suite struct PaymentOutcomeTests {
    private static let failures: [PurchaseManager.MockOutcome] = [
        .failure("The network connection was lost."),
        .failure("Payment is not allowed on this device."),
        .failure("Cannot connect to iTunes Store."),
        .failure("Your purchase could not be completed."),
        .failure("An unknown error occurred."),
    ]
    private static let allOutcomes: [PurchaseManager.MockOutcome] =
        [.success, .cancelled] + failures

    // 7 outcomes — full state + last-event check.
    @Test(arguments: allOutcomes)
    func outcomeDrivesStateAndEvents(_ outcome: PurchaseManager.MockOutcome) async {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        pm.mockOutcome = outcome
        await pm.purchasePro()

        #expect(pm.tracker.count(of: .purchaseStarted) == 1)   // always recorded first
        switch outcome {
        case .success:
            #expect(pm.isPro)
            #expect(pm.lastError == nil)
            #expect(pm.tracker.lastEvent?.event == .purchaseCompleted)
            #expect(pm.tracker.lastEvent?.detail == LicenseConfig.proProductID)
        case .cancelled:
            #expect(!pm.isPro)
            #expect(pm.lastError == nil)
            #expect(pm.tracker.lastEvent?.event == .purchaseCancelled)
        case .failure(let message):
            #expect(!pm.isPro)
            #expect(pm.lastError == message)
            #expect(pm.tracker.lastEvent?.event == .purchaseFailed)
            #expect(pm.tracker.lastEvent?.detail == message)
        }
    }

    // 7 outcomes × 5 features = 35 — gating tracks the outcome for every Pro feature.
    @Test(arguments: allOutcomes, ProFeature.allCases)
    func gatingFollowsOutcomePerFeature(_ outcome: PurchaseManager.MockOutcome, _ feature: ProFeature) async {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        #expect(!pm.canUse(feature))                 // locked before any purchase
        pm.mockOutcome = outcome
        await pm.purchasePro()
        #expect(pm.canUse(feature) == (outcome == .success))
        #expect(pm.indicator(for: feature) == (outcome == .success ? .unlocked : .locked))
        #expect(pm.shouldShowPaywall(for: feature) == (outcome != .success))
    }

    // 5 features — a failed purchase clears lastError when a later purchase succeeds.
    @Test(arguments: ProFeature.allCases)
    func lastErrorClearedOnRetrySuccess(_ feature: ProFeature) async {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        pm.mockOutcome = .failure("boom")
        await pm.purchasePro()
        #expect(pm.lastError == "boom")
        #expect(!pm.canUse(feature))
        pm.mockOutcome = .success
        await pm.purchasePro()
        #expect(pm.lastError == nil)
        #expect(pm.canUse(feature))
    }

    // 5 features — buying twice stays unlocked and double-counts the funnel events.
    @Test(arguments: ProFeature.allCases)
    func doublePurchaseIsIdempotentForState(_ feature: ProFeature) async {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        await pm.purchasePro()
        await pm.purchasePro()
        #expect(pm.isPro)
        #expect(pm.canUse(feature))
        #expect(pm.tracker.count(of: .purchaseStarted) == 2)
        #expect(pm.tracker.count(of: .purchaseCompleted) == 2)
    }

    // 5 cancel'd features stay locked and route to the paywall.
    @Test(arguments: ProFeature.allCases)
    func cancelLeavesFeatureLocked(_ feature: ProFeature) async {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        pm.mockOutcome = .cancelled
        await pm.purchasePro()
        #expect(!pm.canUse(feature))
        #expect(pm.shouldShowPaywall(for: feature))
        #expect(pm.tracker.count(of: .purchaseCancelled) == 1)
        #expect(pm.tracker.count(of: .purchaseCompleted) == 0)
    }
}
