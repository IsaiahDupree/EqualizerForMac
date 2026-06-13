import SwiftUI

/// Sonance EQ Pro paywall. Drives `PurchaseManager` — in mock mode the buy/restore flow is fully
/// functional (persists locally, no charge); with a real RevenueCat key it runs live StoreKit.
struct PaywallView: View {
    @Bindable var app: AppState
    @Environment(\.dismiss) private var dismiss

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
                Text(app.license.store == .mock ? "Unlock Pro (mock) · $19.99" : "Unlock Pro · $19.99")
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
    }
}
