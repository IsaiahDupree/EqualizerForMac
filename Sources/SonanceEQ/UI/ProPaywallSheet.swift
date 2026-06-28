import SwiftUI
import RevenueCat
import RevenueCatUI

/// The Pro paywall presented throughout the app. It picks the best available paywall:
///
/// - **RevenueCat dashboard paywall** (`RevenueCatUI.PaywallView`) when the live store is configured
///   AND the current offering actually has a paywall designed in the RevenueCat dashboard — so design,
///   copy, and pricing are remote-managed and A/B-testable, and the price is the real StoreKit price.
/// - **Native paywall** (`MockPaywallView`) otherwise — the offline dev/mock store, *and* the live store
///   when no dashboard paywall exists yet. Either way purchases route through the RevenueCat SDK, so
///   **payment data still reports to RevenueCat** regardless of which paywall shows.
///
/// This means we can ship without a dashboard paywall (native shows) and it auto-upgrades to the
/// RevenueCat paywall the moment one is designed — no app update needed.
struct ProPaywallSheet: View {
    @Bindable var app: AppState
    @Environment(\.dismiss) private var dismiss

    /// nil = still deciding, true = offering has a dashboard paywall, false = fall back to native.
    @State private var hasDashboardPaywall: Bool?

    var body: some View {
        Group {
            if app.license.store != .revenueCat || !app.license.isConfigured {
                MockPaywallView(app: app)                       // dev / mock store
            } else if hasDashboardPaywall == true {
                revenueCatPaywall                                // live + dashboard paywall designed
            } else if hasDashboardPaywall == false {
                MockPaywallView(app: app)                        // live but no dashboard paywall yet
            } else {
                ProgressView().controlSize(.small).padding(40)   // deciding
                    .task { await decide() }
            }
        }
    }

    private var revenueCatPaywall: some View {
        PaywallView(displayCloseButton: true)
            .onPurchaseStarted { _ in
                app.license.tracker.record(.purchaseStarted, store: "revenueCat")
            }
            .onPurchaseCompleted { _ in
                app.license.tracker.record(.purchaseCompleted, store: "revenueCat",
                                           detail: LicenseConfig.proProductID)
                finish()
            }
            .onPurchaseCancelled {
                app.license.tracker.record(.purchaseCancelled, store: "revenueCat")
            }
            .onRestoreCompleted { _ in
                app.license.tracker.record(.restoreCompleted, store: "revenueCat")
                finish()
            }
    }

    private func decide() async {
        let offering = try? await Purchases.shared.offerings().current
        hasDashboardPaywall = offering?.hasPaywall ?? false
    }

    private func finish() {
        Task { await app.license.refresh() }
        dismiss()
    }
}
