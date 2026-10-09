import SwiftUI
import RevenueCat
import RevenueCatUI

/// The Pro paywall presented throughout the app. It picks the best available paywall:
///
/// - **RevenueCat dashboard paywall** when the resolved English offering has a hosted paywall and
///   contains only the approved one-time Pro package. The exact offering drives display and purchase.
/// - **Native paywall** (`MockPaywallView`) otherwise — the offline dev/mock store, *and* the live store
///   when no dashboard paywall exists yet. Either way purchases route through the RevenueCat SDK, so
///   **payment data still reports to RevenueCat** regardless of which paywall shows.
///
/// Other app languages use the bundled native translations until hosted localization is verified.
struct ProPaywallSheet: View {
    @Bindable var app: AppState
    @Environment(\.dismiss) private var dismiss

    /// nil = still deciding, true = offering has a dashboard paywall, false = fall back to native.
    @State private var hasDashboardPaywall: Bool?
    @State private var dashboardOffering: Offering?

    var body: some View {
        Group {
            if app.license.store != .revenueCat || !app.license.isConfigured {
                MockPaywallView(app: app)                       // dev / mock store
            } else if hasDashboardPaywall == true, let dashboardOffering {
                revenueCatPaywall(offering: dashboardOffering)                                // live + dashboard paywall designed
            } else if hasDashboardPaywall == false {
                MockPaywallView(app: app)                        // live but no dashboard paywall yet
            } else {
                VStack(spacing: 12) {                            // deciding — cancellable so a slow
                    ProgressView().controlSize(.small)           // offerings() fetch can't modal-lock
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                .padding(40)
                .task { await decide() }
            }
        }
    }

    private func revenueCatPaywall(offering: Offering) -> some View {
        PaywallView(offering: offering, displayCloseButton: true)
            .onPurchaseStarted { _ in
                app.license.lastError = nil
                app.license.tracker.record(.purchaseStarted, store: "revenueCat")
            }
            .onPurchaseCompleted { info in
                if app.license.completePurchase(info) { dismiss() }
            }
            .onPurchaseCancelled {
                app.license.tracker.record(.purchaseCancelled, store: "revenueCat")
            }
            .onRestoreStarted {
                app.license.lastError = nil
                app.license.tracker.record(.restoreStarted, store: "revenueCat")
            }
            .onRestoreCompleted { info in
                if app.license.completeRestore(info) { dismiss() }
            }
            .onPurchaseFailure { error in
                app.license.lastError = error.localizedDescription
                app.license.tracker.record(.purchaseFailed, store: "revenueCat", detail: error.localizedDescription)
            }
            .onRestoreFailure { error in
                app.license.lastError = error.localizedDescription
                app.license.tracker.record(.restoreFailed, store: "revenueCat", detail: error.localizedDescription)
            }
            .safeAreaInset(edge: .bottom) {
                if let error = app.license.lastError {
                    Text(error).font(.caption).foregroundStyle(.red).padding()
                }
            }
    }

    private func decide() async {
        do {
            let offering = try await app.license.loadProOffering()
            // Hosted translations need separate verification. Until then, non-English app
            // languages use the complete native catalogs, including distinct pt-PT/zh-Hant.
            let language = Bundle.main.preferredLocalizations.first ?? "en"
            let eligible = language.hasPrefix("en") && offering.hasPaywall
                && offering.availablePackages.count == 1
                && PurchaseManager.proPackage(in: offering) != nil
            dashboardOffering = eligible ? offering : nil
            hasDashboardPaywall = eligible
        } catch {
            app.license.lastError = error.localizedDescription
            hasDashboardPaywall = false
        }
    }
}
