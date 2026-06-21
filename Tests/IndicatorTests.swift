import Foundation
import Testing
@testable import SonanceEQ

/// The pure indicator model the UI consumes: `ProIndicator`, its symbol selection, and the
/// `indicator(for:)` / `shouldShowPaywall(for:)` decisions on `PurchaseManager`.
@MainActor
@Suite struct IndicatorTests {

    // 5 features × 2 entitlement states = 10 — indicator + paywall routing track entitlement.
    @Test(arguments: ProFeature.allCases, [false, true])
    func indicatorReflectsEntitlement(_ feature: ProFeature, _ unlocked: Bool) {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        if unlocked { pm.mockUnlock() }
        #expect(pm.indicator(for: feature) == (unlocked ? .unlocked : .locked))
        #expect(pm.shouldShowPaywall(for: feature) == !unlocked)
        #expect(pm.canUse(feature) == unlocked)
    }

    // 7 glyphs × 2 states = 14 — symbol(unlocked:) yields the natural glyph or the lock.
    @Test(arguments: unlockedGlyphs, [ProIndicator.unlocked, ProIndicator.locked])
    func symbolForState(_ glyph: String, _ state: ProIndicator) {
        let symbol = state.symbol(unlocked: glyph)
        switch state {
        case .unlocked: #expect(symbol == glyph)
        case .locked:   #expect(symbol == ProIndicator.lockedSymbol)
        }
    }

    @Test func lockedSymbolIsTheSharedConstant() {
        #expect(ProIndicator.lockedSymbol == "lock.fill")
        #expect(ProIndicator.locked.symbol(unlocked: "anything") == "lock.fill")
        #expect(ProIndicator.unlocked.symbol(unlocked: "headphones") == "headphones")
    }

    // 5 features — locked controls route to the paywall; unlocked controls run their action.
    @Test(arguments: ProFeature.allCases)
    func paywallRoutingMatchesEntitlement(_ feature: ProFeature) async {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        #expect(pm.shouldShowPaywall(for: feature))      // locked → paywall
        await pm.purchasePro()
        #expect(!pm.shouldShowPaywall(for: feature))     // unlocked → action
    }
}
