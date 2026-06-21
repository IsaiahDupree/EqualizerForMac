import Foundation
import OSLog
import RevenueCat

/// Owns licensing state: configures RevenueCat (when a real key is present) or a **mock store**
/// (until then), tracks the Pro entitlement, runs purchase/restore, and records the conversion
/// funnel via `PurchaseEventTracker`.
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

    /// Outcome the **mock** store should simulate for the next purchase. The default (`.success`)
    /// keeps shipping behaviour unchanged; `.cancelled` / `.failure` let the cancel and failure code
    /// paths (and their tracked events) be exercised without StoreKit. Mock-store only.
    enum MockOutcome: Equatable, Sendable {
        case success
        case cancelled
        case failure(String)
    }

    private(set) var isPro = false
    private(set) var isConfigured = false      // true once the live RevenueCat SDK is configured
    private(set) var store: Store = .mock
    var lastError: String?

    /// Mock-store purchase outcome (see `MockOutcome`). Ignored by the live RevenueCat store.
    var mockOutcome: MockOutcome = .success

    let tracker: PurchaseEventTracker

    private let defaults: UserDefaults
    private let mockKey = "mockProUnlocked"
    private let log = Logger(subsystem: kSubsystem, category: "Purchases")
    // `nonisolated(unsafe)` so the nonisolated `deinit` can cancel it; a `Task?` is safe to cancel
    // from any thread, and it's only assigned once (on the main actor, in `start()`).
    nonisolated(unsafe) private var customerInfoTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, tracker: PurchaseEventTracker? = nil) {
        self.defaults = defaults
        self.tracker = tracker ?? PurchaseEventTracker(defaults: defaults)
    }

    deinit { customerInfoTask?.cancel() }

    /// Human-readable store tag for tracked events.
    private var storeName: String { store == .mock ? "mock" : "revenueCat" }

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
        tracker.record(.configured, store: storeName)
        // Listen for every entitlement change RevenueCat surfaces — app-initiated or not (renewals,
        // refunds, Ask-to-Buy, other-device purchases, dashboard grants all arrive here).
        customerInfoTask = Task { @MainActor [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
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
        lastError = nil
        tracker.record(.purchaseStarted, store: storeName)
        switch store {
        case .mock:
            switch mockOutcome {
            case .success:
                defaults.set(true, forKey: mockKey)
                isPro = true
                tracker.record(.purchaseCompleted, store: storeName, detail: LicenseConfig.proProductID)
                log.notice("MOCK purchase completed — Pro unlocked.")
            case .cancelled:
                tracker.record(.purchaseCancelled, store: storeName)
                log.notice("MOCK purchase cancelled.")
            case .failure(let message):
                lastError = message
                tracker.record(.purchaseFailed, store: storeName, detail: message)
                log.error("MOCK purchase failed: \(message, privacy: .public)")
            }
        case .revenueCat:
            guard isConfigured else { return }
            do {
                let offerings = try await Purchases.shared.offerings()
                let offering = offerings.current ?? offerings.offering(identifier: LicenseConfig.offeringID)
                guard let package = offering?.availablePackages.first else {
                    lastError = "No purchase option is available right now."
                    tracker.record(.purchaseFailed, store: storeName, detail: lastError)
                    return
                }
                let result = try await Purchases.shared.purchase(package: package)
                if result.userCancelled {
                    tracker.record(.purchaseCancelled, store: storeName)
                } else {
                    apply(result.customerInfo)
                    tracker.record(.purchaseCompleted, store: storeName, detail: LicenseConfig.proProductID)
                }
            } catch {
                report(error, "purchase")
                tracker.record(.purchaseFailed, store: storeName, detail: error.localizedDescription)
            }
        }
    }

    /// Restore a previous purchase.
    func restore() async {
        lastError = nil
        tracker.record(.restoreStarted, store: storeName)
        switch store {
        case .mock:
            isPro = defaults.bool(forKey: mockKey)
            tracker.record(isPro ? .restoreCompleted : .restoreNoEntitlement, store: storeName)
        case .revenueCat:
            guard isConfigured else { return }
            do {
                apply(try await Purchases.shared.restorePurchases())
                tracker.record(isPro ? .restoreCompleted : .restoreNoEntitlement, store: storeName)
            } catch {
                report(error, "restore")
                tracker.record(.restoreFailed, store: storeName, detail: error.localizedDescription)
            }
        }
    }

    /// Record that the paywall was presented (the top of the conversion funnel).
    func paywallShown() {
        tracker.record(.paywallShown, store: storeName)
    }

    /// Mock-store only: relock so the paywall + gating can be re-tested.
    func mockRelock() {
        guard store == .mock else { return }
        defaults.set(false, forKey: mockKey)
        isPro = false
    }

    /// Mock-store only: unlock synchronously (used by `--demo` launches / screenshots).
    func mockUnlock() {
        guard store == .mock else { return }
        defaults.set(true, forKey: mockKey)
        isPro = true
    }

    /// Single place that decides what Pro unlocks.
    func canUse(_ feature: ProFeature) -> Bool { isPro }

    // MARK: - Indicators (pure, shared by UI + tests)

    /// What a Pro-gated control should display for `feature` given the current entitlement.
    func indicator(for feature: ProFeature) -> ProIndicator { canUse(feature) ? .unlocked : .locked }

    /// Whether tapping a `feature` control should open the paywall instead of running its action.
    func shouldShowPaywall(for feature: ProFeature) -> Bool { !canUse(feature) }

    // MARK: - Entitlement policy (pure, the actual "is this user paid?" decision)

    /// Pro is unlocked **only** when RevenueCat reports the configured entitlement among the customer's
    /// validated, currently-active entitlements. **Fail-closed:** an empty set (no purchase), a
    /// *different* entitlement, or an inactive/expired/refunded one (which RevenueCat omits from
    /// `.active`) all resolve to locked. RevenueCat does the receipt/transaction validation server-side;
    /// this is the on-device policy that trusts only that validated signal.
    static func isProActive(in activeEntitlementIDs: Set<String>) -> Bool {
        activeEntitlementIDs.contains(LicenseConfig.proEntitlementID)
    }

    /// Apply a validated set of active entitlement ids (from RevenueCat `CustomerInfo.entitlements.active`).
    /// Drives `isPro` through the single policy above — the one gate every Pro feature funnels through.
    func applyActiveEntitlements(_ activeEntitlementIDs: Set<String>) {
        isPro = Self.isProActive(in: activeEntitlementIDs)
    }

    /// Apply a validated active set **and record the lifecycle events** it implies: always a
    /// `customerInfoUpdated`, plus `entitlementGranted` / `entitlementRevoked` when Pro flips. This is
    /// the single funnel every RevenueCat/Apple-originated entitlement change passes through, so the
    /// in-app tracker (and the analytics view) see unlocks/revokes regardless of where they came from.
    func applyAndTrack(_ activeEntitlementIDs: Set<String>) {
        let was = isPro
        applyActiveEntitlements(activeEntitlementIDs)
        tracker.record(.customerInfoUpdated, store: storeName)
        if isPro && !was {
            tracker.record(.entitlementGranted, store: storeName)
        } else if !isPro && was {
            tracker.record(.entitlementRevoked, store: storeName)
        }
    }

    // MARK: - Private

    private func apply(_ info: CustomerInfo) {
        // `.active` already contains only entitlements RevenueCat validated as currently active.
        applyAndTrack(Set(info.entitlements.active.keys))
    }

    private func report(_ error: Error, _ op: String) {
        lastError = error.localizedDescription
        log.error("\(op, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }
}

/// The visual state of a Pro-gated control. The actual SF Symbol for the locked state is
/// `ProIndicator.lockedSymbol`; the unlocked symbol is feature-specific (chosen at the call site).
enum ProIndicator: Equatable {
    case unlocked
    case locked

    /// SF Symbol shown when a feature is locked. One constant so every gate looks identical.
    static let lockedSymbol = "lock.fill"

    /// The symbol to show for a gated control: its natural `unlocked` symbol, or the lock when locked.
    func symbol(unlocked: String) -> String {
        switch self {
        case .unlocked: return unlocked
        case .locked:   return Self.lockedSymbol
        }
    }
}
