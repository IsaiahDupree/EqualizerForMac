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

    /// Only real StoreKit package prices appear on the live paywall.
    @State private var package: Package?
    @State private var loading = true

    /// Keep these as `LocalizedStringKey` values. Passing runtime `String` values to `Label` would
    /// render the English source text verbatim and silently bypass Localizable.strings.
    private let features: [(id: String, icon: String, text: LocalizedStringKey)] = [
        ("headphones", "headphones", "8,850 AutoEq headphone corrections"),
        ("parametric", "slider.horizontal.3", "Full parametric EQ — up to 32 bands"),
        ("linear-phase", "waveform.path", "Linear-phase mode"),
        ("mid-side", "circle.lefthalf.filled", "Mid-Side EQ (center vs. width)"),
        ("presets", "square.and.arrow.up.on.square", "Import & export presets"),
    ]

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 46)).foregroundStyle(.tint)
            Text("Sonance EQ Pro").font(.title.bold())
            Text("Unlock the full equalizer — a one-time purchase.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(features, id: \.id) { f in
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
                Task { if await app.license.purchasePro(package: package) { dismiss() } }
            } label: {
                Group {
                    if app.license.store == .mock {
                        Text("Unlock Pro (mock)")
                    } else if let package {
                        Text("Unlock Pro · \(package.storeProduct.localizedPriceString)")
                    } else {
                        Text("Unlock Pro")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(app.license.isProcessing || (app.license.store == .revenueCat && package == nil))

            if app.license.store == .revenueCat && package == nil {
                if loading { ProgressView().controlSize(.small) }
                else { Button("Try again") { Task { await loadPackage() } } }
            }

            HStack {
                Button("Restore Purchase") {
                    Task { if await app.license.restore() { dismiss() } }
                }
                if app.license.store == .mock && app.license.isPro {
                    Spacer()
                    Button("Relock (mock)") { app.license.mockRelock() }
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.small)
            .disabled(app.license.isProcessing)

            if let error = app.license.lastError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
            Button("Not now") { dismiss() }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 380)
        .task { await loadPackage() }
    }

    private func loadPackage() async {
        guard app.license.store == .revenueCat else { loading = false; return }
        loading = true
        defer { loading = false }
        do {
            package = try await app.license.loadProPackage()
            app.license.lastError = nil
        } catch {
            package = nil
            app.license.lastError = error.localizedDescription
        }
    }
}
