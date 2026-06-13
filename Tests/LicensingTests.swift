import Foundation
import Testing
@testable import SonanceEQ

@Suite struct LicenseConfigTests {
    @Test func unconfiguredByDefault() {
        #expect(LicenseConfig.isUnconfigured)
        #expect(LicenseConfig.revenueCatPublicAPIKey == LicenseConfig.unconfiguredSentinel)
    }

    @Test func entitlementIdentifier() { #expect(LicenseConfig.proEntitlementID == "pro") }
    @Test func productIdentifier() { #expect(LicenseConfig.proProductID == "com.isaiahdupree.SonanceEQ.pro") }
    @Test func offeringIdentifier() { #expect(LicenseConfig.offeringID == "default") }
    @Test func fourProFeatures() { #expect(ProFeature.allCases.count == 4) }
}

@MainActor
@Suite struct PurchaseManagerMockTests {
    private func freshManager() -> (PurchaseManager, UserDefaults, String) {
        let suite = "test.purchases.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (PurchaseManager(defaults: defaults), defaults, suite)
    }

    @Test func startsInMockStoreLocked() {
        let (pm, _, suite) = freshManager()
        pm.start()
        #expect(pm.store == .mock)
        #expect(pm.isPro == false)        // default locked → paywall is visible
        #expect(pm.isConfigured == false) // no real key → never configured RevenueCat
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func mockPurchaseUnlocksAndPersists() async {
        let (pm, defaults, suite) = freshManager()
        pm.start()
        await pm.purchasePro()
        #expect(pm.isPro)
        // A new manager on the same store restores the unlock.
        let pm2 = PurchaseManager(defaults: defaults)
        pm2.start()
        #expect(pm2.isPro)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func mockRelockReturnsToLocked() async {
        let (pm, _, suite) = freshManager()
        pm.start()
        await pm.purchasePro()
        #expect(pm.isPro)
        pm.mockRelock()
        #expect(!pm.isPro)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func restoreReflectsStoredState() async {
        let (pm, _, suite) = freshManager()
        pm.start()
        await pm.restore()
        #expect(!pm.isPro)                // nothing purchased yet
        await pm.purchasePro()
        await pm.restore()
        #expect(pm.isPro)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    // Every Pro feature is gated while locked and available once unlocked.
    @Test(arguments: ProFeature.allCases)
    func featureGatingFollowsEntitlement(_ feature: ProFeature) async {
        let (pm, _, suite) = freshManager()
        pm.start()
        #expect(!pm.canUse(feature))
        await pm.purchasePro()
        #expect(pm.canUse(feature))
        UserDefaults().removePersistentDomain(forName: suite)
    }
}
