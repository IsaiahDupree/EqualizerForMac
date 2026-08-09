import Foundation
import RevenueCat

/// The two `Offerings` reads `PurchaseManager` actually performs when resolving which package to buy:
/// the dashboard's current offering, or a fallback looked up by id. RevenueCat's `Offerings` has no
/// public initializer (it's only buildable from a real backend/cache response), so this protocol lets
/// tests supply a lightweight stand-in built from `Offering`/`Package`/`TestStoreProduct` — all of which
/// RevenueCat *does* expose public initializers for — without needing a live `Offerings` instance.
/// `RevenueCat.Offerings` already has matching members, so it conforms for free below; the live path is
/// unchanged.
protocol OfferingsResolving {
    var current: Offering? { get }
    func offering(identifier: String?) -> Offering?
}

extension Offerings: OfferingsResolving {}

/// The slice of the RevenueCat `Purchases` SDK that `PurchaseManager`'s `.revenueCat` store calls.
/// Exists so `purchasePro()` / `restore()` / `refresh()` can be driven, end to end, against a fake in
/// tests — the real `Purchases.shared` singleton is process-global and `Purchases.configure(...)` is a
/// one-time side-effecting call, so it can't be exercised repeatedly (or without network) from unit tests.
protocol PurchaseProviding: Sendable {
    func offerings() async throws -> OfferingsResolving
    func purchase(package: Package) async throws -> PurchaseResultData
    func restorePurchases() async throws -> CustomerInfo
    func customerInfo() async throws -> CustomerInfo
    var customerInfoStream: AsyncStream<CustomerInfo> { get }
}

/// Live implementation: forwards straight to the configured `Purchases.shared` SDK singleton.
struct RevenueCatProvider: PurchaseProviding {
    func offerings() async throws -> OfferingsResolving { try await Purchases.shared.offerings() }

    func purchase(package: Package) async throws -> PurchaseResultData {
        try await Purchases.shared.purchase(package: package)
    }

    func restorePurchases() async throws -> CustomerInfo { try await Purchases.shared.restorePurchases() }

    func customerInfo() async throws -> CustomerInfo { try await Purchases.shared.customerInfo() }

    var customerInfoStream: AsyncStream<CustomerInfo> { Purchases.shared.customerInfoStream }
}
