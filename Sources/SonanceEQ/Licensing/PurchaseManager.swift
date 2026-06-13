import Foundation
import OSLog
import RevenueCat

/// Owns licensing state: configures RevenueCat (when a real key is present) or a **mock store**
/// (until then), tracks the Pro entitlement, and runs purchase/restore.
///
/// **Mock store (M3 development):** while `LicenseConfig.isUnconfigured`, this never touches the network.
/// It persists a single "purchased" flag in `UserDefaults`, so the whole paywall → buy → unlock → relaunch
/// → gating flow works end-to-end with no Apple registration. Default is **locked** so the paywall and
/// feature gates are visible/testable. `mockRelock()` re-locks for re-testing. When a real RevenueCat
/// public key is filled into `LicenseConfig`, `start()` switches to the live `.revenueCat` path unchanged.
@MainActor
@Observable
final class PurchaseManager {
    enum Store { case mock, revenueCat }

    private(set) var isPro = false
    private(set) var isConfigured = false      // true once the live RevenueCat SDK is configured
    private(set) var store: Store = .mock
    var lastError: String?

    private let defaults: UserDefaults
    private let mockKey = "mockProUnlocked"
    private let log = Logger(subsystem: kSubsystem, category: "Purchases")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Call once at launch.
    func start() {
        guard !LicenseConfig.isUnconfigured else {
            store = .mock
            isPro = defaults.bool(forKey: mockKey)
            log.notice("RevenueCat not configured — MOCK store (Pro \(self.isPro ? "unlocked" : "locked", privacy: .public)).")
            return
        }
        store = .revenueCat
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: LicenseConfig.revenueCatPublicAPIKey)
        isConfigured = true
        Task { await refresh() }
    }

    /// Re-read the current entitlement.
    func refresh() async {
        switch store {
        case .mock:
            isPro = defaults.bool(forKey: mockKey)
        case .revenueCat:
            guard isConfigured else { return }
            do { apply(try await Purchases.shared.customerInfo()) }
            catch { report(error, "customerInfo") }
        }
    }

    /// Buy the one-time Pro unlock.
    func purchasePro() async {
        switch store {
        case .mock:
            defaults.set(true, forKey: mockKey)
            isPro = true
            log.notice("MOCK purchase completed — Pro unlocked.")
        case .revenueCat:
            guard isConfigured else { return }
            do {
                let offerings = try await Purchases.shared.offerings()
                let offering = offerings.current ?? offerings.offering(identifier: LicenseConfig.offeringID)
                guard let package = offering?.availablePackages.first else {
                    lastError = "No purchase option is available right now."
                    return
                }
                apply(try await Purchases.shared.purchase(package: package).customerInfo)
            } catch {
                report(error, "purchase")
            }
        }
    }

    /// Restore a previous purchase.
    func restore() async {
        switch store {
        case .mock:
            isPro = defaults.bool(forKey: mockKey)
        case .revenueCat:
            guard isConfigured else { return }
            do { apply(try await Purchases.shared.restorePurchases()) }
            catch { report(error, "restore") }
        }
    }

    /// Mock-store only: relock so the paywall + gating can be re-tested.
    func mockRelock() {
        guard store == .mock else { return }
        defaults.set(false, forKey: mockKey)
        isPro = false
    }

    /// Single place that decides what Pro unlocks.
    func canUse(_ feature: ProFeature) -> Bool { isPro }

    // MARK: - Private

    private func apply(_ info: CustomerInfo) {
        isPro = info.entitlements[LicenseConfig.proEntitlementID]?.isActive == true
    }

    private func report(_ error: Error, _ op: String) {
        lastError = error.localizedDescription
        log.error("\(op, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }
}
