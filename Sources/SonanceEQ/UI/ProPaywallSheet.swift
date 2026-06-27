import SwiftUI
import RevenueCat
import RevenueCatUI

/// The Pro paywall presented throughout the app.
///
/// - **Live (RevenueCat configured):** shows RevenueCat's **dashboard-managed** `PaywallView` — the
///   design, copy, and pricing come from the RevenueCat dashboard (the `default` offering), so they can
///   be changed and A/B-tested without an app update, and the price is always the real StoreKit price.
/// - **Mock (RevenueCat not configured — offline dev, tests, screenshots):** falls back to
///   `MockPaywallView`, which drives the mock store with no network.
///
/// Purchase/restore go through the RevenueCat SDK directly; we mirror the funnel into our
/// `PurchaseEventTracker` via the completion modifiers and refresh entitlement state on completion
/// (the `customerInfoStream` listener also catches the grant).
struct ProPaywallSheet: View {
    @Bindable var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if app.license.store == .revenueCat && app.license.isConfigured {
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
        } else {
            MockPaywallView(app: app)
        }
    }

    private func finish() {
        Task { await app.license.refresh() }
        dismiss()
    }
}
