import Foundation
import OSLog
import RevenueCat

/// Owns the licensing state: configures RevenueCat, tracks Pro entitlement, and runs purchase/restore.
///
/// **Dev/eval safety:** when no real RevenueCat key is wired (`LicenseConfig.isUnconfigured`), this never
/// touches the network and reports Pro-unlocked — so M0–M2 development and the headless compile-check are
/// unaffected. The real entitlement check only runs once a public key is filled in for M3.
@MainActor
@Observable
final class PurchaseManager {
    /// Whether Pro features are unlocked. Always `true` in unconfigured dev/eval builds.
    private(set) var isPro = false
    /// True once RevenueCat has actually been configured with a real key.
    private(set) var isConfigured = false
    /// Last user-facing purchase/restore error, if any.
    var lastError: String?

    private let log = Logger(subsystem: kSubsystem, category: "Purchases")

    /// Call once at launch.
    func start() {
        guard !LicenseConfig.isUnconfigured else {
            isPro = true
            log.notice("RevenueCat not configured — running Pro-unlocked (dev/eval build).")
            return
        }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: LicenseConfig.revenueCatPublicAPIKey)
        isConfigured = true
        Task { await refresh() }
    }

    /// Re-read the current entitlement (e.g. after returning to foreground).
    func refresh() async {
        guard isConfigured else { return }
        do { apply(try await Purchases.shared.customerInfo()) }
        catch { report(error, "customerInfo") }
    }

    /// Buy the one-time Pro unlock from the current offering.
    func purchasePro() async {
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

    /// Restore a previous one-time purchase on this Apple ID.
    func restore() async {
        guard isConfigured else { return }
        do { apply(try await Purchases.shared.restorePurchases()) }
        catch { report(error, "restore") }
    }

    /// Single place that decides what Pro unlocks. Today: all advanced features gate on `isPro`.
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
