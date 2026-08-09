import Foundation
import RevenueCat
import Testing
@testable import SonanceEQ

/// Exercises the `.revenueCat` branches of `purchasePro()` / `restore()` / `refresh()` — the actual
/// live-money code path, previously compiled but never run by any test (`StoreKitIntegrationTests`
/// only drives `applyActiveEntitlements` directly, bypassing these). Uses `FakePurchaseProvider`
/// (`PurchaseProviding`) so the offering/package resolution, cancel/success/error result-mapping, and
/// tracked-event side effects run for real with no network and no Apple registration.
@MainActor
@Suite struct RevenueCatPurchaseFlowTests {

    // MARK: - purchasePro()

    @Test func purchaseResolvesCurrentOfferingAndUnlocksPro() async {
        let provider = FakePurchaseProvider()
        let package = RevenueCatTestKit.package()
        provider.offeringsResult = .success(RevenueCatTestKit.FakeOfferings(
            current: RevenueCatTestKit.offering(packages: [package])
        ))
        provider.purchaseResult = .success((transaction: nil, customerInfo: RevenueCatTestKit.customerInfo(proActive: true),
                                             userCancelled: false))
        let (pm, _, suite) = RevenueCatTestKit.makeLiveManager(provider: provider)
        defer { LicensingTestKit.dispose(suite) }

        await pm.purchasePro()

        #expect(pm.isPro)
        #expect(pm.lastError == nil)
        #expect(provider.purchasedPackages.map(\.identifier) == [package.identifier])
        #expect(pm.tracker.lastEvent?.event == .purchaseCompleted)
        #expect(pm.tracker.lastEvent?.detail == LicenseConfig.proProductID)
    }

    // No `current` offering configured — falls back to the named offering, matching
    // `offerings.current ?? offerings.offering(identifier: LicenseConfig.offeringID)`.
    @Test func purchaseFallsBackToNamedOfferingWhenNoCurrentOffering() async {
        let provider = FakePurchaseProvider()
        let package = RevenueCatTestKit.package(id: "fallback_pkg")
        provider.offeringsResult = .success(RevenueCatTestKit.FakeOfferings(
            current: nil,
            named: [LicenseConfig.offeringID: RevenueCatTestKit.offering(packages: [package])]
        ))
        provider.purchaseResult = .success((transaction: nil, customerInfo: RevenueCatTestKit.customerInfo(proActive: true),
                                             userCancelled: false))
        let (pm, _, suite) = RevenueCatTestKit.makeLiveManager(provider: provider)
        defer { LicensingTestKit.dispose(suite) }

        await pm.purchasePro()

        #expect(pm.isPro)
        #expect(provider.purchasedPackages.map(\.identifier) == ["fallback_pkg"])
    }

    // Neither a current nor a named offering resolves — must fail closed without ever calling purchase().
    @Test func purchaseWithNoOfferingFailsWithoutAttemptingPurchase() async {
        let provider = FakePurchaseProvider()
        provider.offeringsResult = .success(RevenueCatTestKit.FakeOfferings(current: nil))
        let (pm, _, suite) = RevenueCatTestKit.makeLiveManager(provider: provider)
        defer { LicensingTestKit.dispose(suite) }

        await pm.purchasePro()

        #expect(!pm.isPro)
        #expect(pm.lastError == "No purchase option is available right now.")
        #expect(provider.purchasedPackages.isEmpty)
        #expect(pm.tracker.lastEvent?.event == .purchaseFailed)
        #expect(pm.tracker.lastEvent?.detail == pm.lastError)
    }

    // An offering with no packages must also fail closed the same way.
    @Test func purchaseWithEmptyOfferingFailsWithoutAttemptingPurchase() async {
        let provider = FakePurchaseProvider()
        provider.offeringsResult = .success(RevenueCatTestKit.FakeOfferings(
            current: RevenueCatTestKit.offering(packages: [])
        ))
        let (pm, _, suite) = RevenueCatTestKit.makeLiveManager(provider: provider)
        defer { LicensingTestKit.dispose(suite) }

        await pm.purchasePro()

        #expect(!pm.isPro)
        #expect(pm.lastError == "No purchase option is available right now.")
        #expect(provider.purchasedPackages.isEmpty)
    }

    @Test func purchaseUserCancelledLeavesProLockedWithNoError() async {
        let provider = FakePurchaseProvider()
        let package = RevenueCatTestKit.package()
        provider.offeringsResult = .success(RevenueCatTestKit.FakeOfferings(
            current: RevenueCatTestKit.offering(packages: [package])
        ))
        provider.purchaseResult = .success((transaction: nil, customerInfo: RevenueCatTestKit.customerInfo(proActive: false),
                                             userCancelled: true))
        let (pm, _, suite) = RevenueCatTestKit.makeLiveManager(provider: provider)
        defer { LicensingTestKit.dispose(suite) }

        await pm.purchasePro()

        #expect(!pm.isPro)
        #expect(pm.lastError == nil)
        #expect(pm.tracker.lastEvent?.event == .purchaseCancelled)
    }

    @Test func purchaseThrowingErrorSetsLastErrorAndTracksFailure() async {
        let provider = FakePurchaseProvider()
        let package = RevenueCatTestKit.package()
        provider.offeringsResult = .success(RevenueCatTestKit.FakeOfferings(
            current: RevenueCatTestKit.offering(packages: [package])
        ))
        let underlying = RevenueCatTestKit.SimpleError(message: "Cannot connect to iTunes Store.")
        provider.purchaseResult = .failure(underlying)
        let (pm, _, suite) = RevenueCatTestKit.makeLiveManager(provider: provider)
        defer { LicensingTestKit.dispose(suite) }

        await pm.purchasePro()

        #expect(!pm.isPro)
        #expect(pm.lastError == underlying.message)
        #expect(pm.tracker.lastEvent?.event == .purchaseFailed)
        #expect(pm.tracker.lastEvent?.detail == underlying.message)
    }

    // A failed `offerings()` fetch (network down, etc.) must also fail closed and never reach purchase().
    @Test func offeringsFetchFailureFailsClosed() async {
        let provider = FakePurchaseProvider()
        provider.offeringsResult = .failure(RevenueCatTestKit.SimpleError(message: "The network connection was lost."))
        let (pm, _, suite) = RevenueCatTestKit.makeLiveManager(provider: provider)
        defer { LicensingTestKit.dispose(suite) }

        await pm.purchasePro()

        #expect(!pm.isPro)
        #expect(pm.lastError == "The network connection was lost.")
        #expect(provider.purchasedPackages.isEmpty)
        #expect(pm.tracker.lastEvent?.event == .purchaseFailed)
    }

    // MARK: - restore()

    @Test func restoreWithEntitlementUnlocksPro() async {
        let provider = FakePurchaseProvider()
        provider.restoreResult = .success(RevenueCatTestKit.customerInfo(proActive: true))
        let (pm, _, suite) = RevenueCatTestKit.makeLiveManager(provider: provider)
        defer { LicensingTestKit.dispose(suite) }

        await pm.restore()

        #expect(pm.isPro)
        #expect(pm.lastError == nil)
        #expect(pm.tracker.lastEvent?.event == .restoreCompleted)
    }

    @Test func restoreWithoutEntitlementStaysLocked() async {
        let provider = FakePurchaseProvider()
        provider.restoreResult = .success(RevenueCatTestKit.customerInfo(proActive: false))
        let (pm, _, suite) = RevenueCatTestKit.makeLiveManager(provider: provider)
        defer { LicensingTestKit.dispose(suite) }

        await pm.restore()

        #expect(!pm.isPro)
        #expect(pm.tracker.lastEvent?.event == .restoreNoEntitlement)
    }

    @Test func restoreThrowingErrorSetsLastErrorAndTracksFailure() async {
        let provider = FakePurchaseProvider()
        let underlying = RevenueCatTestKit.SimpleError(message: "Receipt is missing or invalid.")
        provider.restoreResult = .failure(underlying)
        let (pm, _, suite) = RevenueCatTestKit.makeLiveManager(provider: provider)
        defer { LicensingTestKit.dispose(suite) }

        await pm.restore()

        #expect(!pm.isPro)
        #expect(pm.lastError == underlying.message)
        #expect(pm.tracker.lastEvent?.event == .restoreFailed)
        #expect(pm.tracker.lastEvent?.detail == underlying.message)
    }

    // MARK: - refresh()

    @Test func refreshAppliesCurrentEntitlement() async {
        let provider = FakePurchaseProvider()
        provider.customerInfoResult = .success(RevenueCatTestKit.customerInfo(proActive: true))
        let (pm, _, suite) = RevenueCatTestKit.makeLiveManager(provider: provider)
        defer { LicensingTestKit.dispose(suite) }

        await pm.refresh()

        #expect(pm.isPro)
    }

    @Test func refreshThrowingErrorSetsLastErrorAndLeavesEntitlementUnchanged() async {
        let provider = FakePurchaseProvider()
        provider.customerInfoResult = .failure(RevenueCatTestKit.SimpleError(message: "Store problem — try again later."))
        let (pm, _, suite) = RevenueCatTestKit.makeLiveManager(provider: provider)
        defer { LicensingTestKit.dispose(suite) }

        await pm.refresh()

        #expect(!pm.isPro)
        #expect(pm.lastError == "Store problem — try again later.")
    }
}
