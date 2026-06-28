import SwiftUI
import RevenueCat

/// Native Pro paywall — the fallback in `ProPaywallSheet`. Shown for the offline **mock store** (dev,
/// tests, screenshots) AND for the **live store when no RevenueCat dashboard paywall is designed yet**.
/// It drives `PurchaseManager` directly, so on the live store its buy button routes through the
/// RevenueCat SDK (`Purchases.shared.purchase`) — meaning **payment data reports to RevenueCat even via
/// this native paywall**. On the mock store it persists locally with no network.
struct MockPaywallView: View {
    @Bindable var app: AppState
    @Environment(\.dismiss) private var dismiss

    /// The displayed price. Starts at the configured price and is replaced with the **real** StoreKit
    /// price (via the RevenueCat offering) on the live store, so the button never shows a stale/wrong
    /// number. The mock store has no real product, so it keeps this fallback.
    @State private var priceText = "$9.99"

    private let features: [(icon: String, text: String)] = [
        ("headphones", "8,850 AutoEq headphone corrections"),
        ("slider.horizontal.3", "Full parametric EQ — up to 32 bands"),
        ("waveform.path", "Linear-phase mode"),
        ("circle.lefthalf.filled", "Mid-Side EQ (center vs. width)"),
        ("square.and.arrow.up.on.square", "Import & export presets"),
    ]

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 46)).foregroundStyle(.tint)
            Text("Sonance EQ Pro").font(.title.bold())
            Text("Unlock the full equalizer — a one-time purchase.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(features, id: \.text) { f in
                    Label(f.text, systemImage: f.icon)
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)

            if app.license.store == .mock {
                Text("Sandbox / mock store — no real charge. Fill a RevenueCat key in LicenseConfig to go live.")
                    .font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
            }

            Button {
                Task { await app.license.purchasePro(); if app.license.isPro { dismiss() } }
            } label: {
                Text(app.license.store == .mock ? "Unlock Pro (mock) · \(priceText)" : "Unlock Pro · \(priceText)")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            HStack {
                Button("Restore Purchase") {
                    Task { await app.license.restore(); if app.license.isPro { dismiss() } }
                }
                if app.license.store == .mock && app.license.isPro {
                    Spacer()
                    Button("Relock (mock)") { app.license.mockRelock() }
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.small)

            if let error = app.license.lastError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
            Button("Not now") { dismiss() }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 380)
        .task {
            // On the live store, show the real StoreKit price from the RevenueCat offering.
            if app.license.store == .revenueCat, app.license.isConfigured,
               let product = try? await Purchases.shared.offerings().current?.availablePackages.first?.storeProduct {
                priceText = product.localizedPriceString
            }
        }
    }
}
