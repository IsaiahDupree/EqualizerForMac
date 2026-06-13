import Foundation
import Testing
@testable import SonanceEQ

@Suite struct LicensingTests {
    @Test func unconfiguredByDefault() {
        #expect(LicenseConfig.isUnconfigured)
        #expect(LicenseConfig.revenueCatPublicAPIKey == LicenseConfig.unconfiguredSentinel)
    }

    @Test func entitlementIdentifier() {
        #expect(LicenseConfig.proEntitlementID == "pro")
    }

    @Test func productIdentifier() {
        #expect(LicenseConfig.proProductID == "com.isaiahdupree.SonanceEQ.pro")
    }

    @Test func offeringIdentifier() {
        #expect(LicenseConfig.offeringID == "default")
    }

    @Test func fourProFeatures() {
        #expect(ProFeature.allCases.count == 4)
    }

    @MainActor @Test(arguments: ProFeature.allCases)
    func devBuildUnlocksFeature(_ feature: ProFeature) {
        let manager = PurchaseManager()
        manager.start()
        #expect(manager.isPro)
        #expect(manager.canUse(feature))
    }

    @MainActor @Test func unconfiguredManagerIsNotConfigured() {
        let manager = PurchaseManager()
        manager.start()
        #expect(manager.isConfigured == false)   // no real key → never touches RevenueCat
    }
}
