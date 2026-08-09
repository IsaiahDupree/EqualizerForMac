import Foundation
import RevenueCat
@testable import SonanceEQ

/// Builders + a fake `PurchaseProviding` for driving `PurchaseManager`'s `.revenueCat` branches.
///
/// `Offerings` has no public initializer (RevenueCat only builds it from a real backend/cache
/// response), so there's no way to fake "what `offerings()` returns" as a real `Offerings`. Everything
/// else — `Offering`, `Package`, `CustomerInfo`, `EntitlementInfo` — ships a public "for unit testing"
/// initializer specifically for this purpose (see their doc comments in the RevenueCat SDK). `PurchaseManager`
/// only ever reads `Offerings.current` / `.offering(identifier:)`, which is exactly what `OfferingsResolving`
/// abstracts, so `FakeOfferings` below stands in for a real `Offerings` without needing one.
enum RevenueCatTestKit {
    struct SimpleError: Error, LocalizedError, Equatable {
        let message: String
        var errorDescription: String? { message }
    }

    /// `OfferingsResolving` stand-in mirroring the two reads `purchasePro()` performs on a real `Offerings`.
    struct FakeOfferings: OfferingsResolving {
        var current: Offering?
        var named: [String: Offering] = [:]
        func offering(identifier: String?) -> Offering? { identifier.flatMap { named[$0] } }
    }

    /// A purchasable package for `LicenseConfig.proProductID`.
    static func package(id: String = "pro_lifetime") -> Package {
        let product = TestStoreProduct(
            localizedTitle: "Sonance EQ Pro",
            price: 19.99,
            currencyCode: "USD",
            localizedPriceString: "$19.99",
            productIdentifier: LicenseConfig.proProductID,
            productType: .nonConsumable,
            localizedDescription: "Unlock Sonance EQ Pro",
            locale: Locale(identifier: "en_US")
        )
        return Package(identifier: id, packageType: .lifetime, storeProduct: product.toStoreProduct(),
                        offeringIdentifier: LicenseConfig.offeringID, webCheckoutUrl: nil)
    }

    static func offering(identifier: String = LicenseConfig.offeringID, packages: [Package]) -> Offering {
        Offering(identifier: identifier, serverDescription: "Default", availablePackages: packages, webCheckoutUrl: nil)
    }

    /// A `CustomerInfo` with (or without) the configured Pro entitlement active.
    static func customerInfo(proActive: Bool) -> CustomerInfo {
        let entitlements: [String: EntitlementInfo] = proActive ? [
            LicenseConfig.proEntitlementID: EntitlementInfo(
                identifier: LicenseConfig.proEntitlementID,
                isActive: true,
                willRenew: false,
                periodType: .normal,
                store: .testStore,
                productIdentifier: LicenseConfig.proProductID,
                isSandbox: true,
                ownershipType: .purchased
            )
        ] : [:]
        return CustomerInfo(
            entitlements: EntitlementInfos(entitlements: entitlements),
            requestDate: LicensingTestKit.fixedClock()(),
            firstSeen: LicensingTestKit.fixedClock()(),
            originalAppUserId: "test-user"
        )
    }

    /// A `PurchaseManager` already on the `.revenueCat` store (bypassing `start()`'s real,
    /// process-global `Purchases.configure(...)`), wired to `provider`.
    @MainActor
    static func makeLiveManager(provider: FakePurchaseProvider) -> (manager: PurchaseManager, defaults: UserDefaults, suite: String) {
        let suite = "test.purchases.revenuecat.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let tracker = PurchaseEventTracker(defaults: defaults, clock: LicensingTestKit.fixedClock())
        let manager = PurchaseManager(defaults: defaults, tracker: tracker, purchaseProvider: provider,
                                       startAsConfiguredRevenueCatStore: true)
        return (manager, defaults, suite)
    }
}

/// Fake `.revenueCat` backend (`PurchaseProviding`). Each result defaults to a distinct "not stubbed"
/// failure so a test that forgets to configure the call it actually exercises fails loudly rather than
/// silently returning a placeholder success.
final class FakePurchaseProvider: PurchaseProviding, @unchecked Sendable {
    var offeringsResult: Result<OfferingsResolving, Error> =
        .failure(RevenueCatTestKit.SimpleError(message: "offerings() not stubbed"))
    var purchaseResult: Result<PurchaseResultData, Error> =
        .failure(RevenueCatTestKit.SimpleError(message: "purchase(package:) not stubbed"))
    var restoreResult: Result<CustomerInfo, Error> =
        .failure(RevenueCatTestKit.SimpleError(message: "restorePurchases() not stubbed"))
    var customerInfoResult: Result<CustomerInfo, Error> =
        .failure(RevenueCatTestKit.SimpleError(message: "customerInfo() not stubbed"))

    /// Packages passed to `purchase(package:)`, in call order — lets tests assert *whether* a purchase
    /// was attempted (e.g. it must never fire when package resolution comes up empty).
    private(set) var purchasedPackages: [Package] = []

    func offerings() async throws -> OfferingsResolving { try offeringsResult.get() }

    func purchase(package: Package) async throws -> PurchaseResultData {
        purchasedPackages.append(package)
        return try purchaseResult.get()
    }

    func restorePurchases() async throws -> CustomerInfo { try restoreResult.get() }

    func customerInfo() async throws -> CustomerInfo { try customerInfoResult.get() }

    // `start()` (not exercised by these tests — see `makeLiveManager`) is the only reader.
    var customerInfoStream: AsyncStream<CustomerInfo> { AsyncStream { $0.finish() } }
}
