import Foundation
import Testing
@testable import SonanceEQ

/// The licensing state machine: every action (unlock/relock/buy·success/cancel/fail/restore) from
/// every baseline, with gating asserted against an independent model of the expected entitlement.
@MainActor
@Suite struct GatingStateMachineTests {
    enum Action: CaseIterable, Sendable {
        case unlock, relock, buySuccess, buyCancel, buyFail, restore
    }

    /// Drive the manager through one action.
    private func apply(_ action: Action, to pm: PurchaseManager) async {
        switch action {
        case .unlock:     pm.mockUnlock()
        case .relock:     pm.mockRelock()
        case .buySuccess: pm.mockOutcome = .success;            await pm.purchasePro()
        case .buyCancel:  pm.mockOutcome = .cancelled;          await pm.purchasePro()
        case .buyFail:    pm.mockOutcome = .failure("declined"); await pm.purchasePro()
        case .restore:    await pm.restore()
        }
    }

    /// Independent model: what `isPro` should be after `action`, given the prior value.
    private func expected(_ action: Action, from pro: Bool) -> Bool {
        switch action {
        case .unlock, .buySuccess: return true
        case .relock:              return false
        case .buyCancel, .buyFail, .restore: return pro   // unchanged
        }
    }

    // 2 baselines × 6 actions × 5 features = 60 — single action, per-feature gating.
    @Test(arguments: [false, true], Action.allCases)
    func singleActionGating(_ baselineUnlocked: Bool, _ action: Action) async {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        if baselineUnlocked { pm.mockUnlock() }
        let want = expected(action, from: baselineUnlocked)
        await apply(action, to: pm)
        #expect(pm.isPro == want)
        for feature in ProFeature.allCases {
            #expect(pm.canUse(feature) == want)
            #expect(pm.indicator(for: feature) == (want ? .unlocked : .locked))
            #expect(pm.shouldShowPaywall(for: feature) == !want)
        }
    }

    // 6 × 6 = 36 — two-action sequences from a locked start, gating vs the model.
    @Test(arguments: Action.allCases, Action.allCases)
    func twoActionSequences(_ first: Action, _ second: Action) async {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        var model = false
        await apply(first, to: pm);  model = expected(first, from: model)
        await apply(second, to: pm); model = expected(second, from: model)
        #expect(pm.isPro == model)
        for feature in ProFeature.allCases { #expect(pm.canUse(feature) == model) }
    }
}
