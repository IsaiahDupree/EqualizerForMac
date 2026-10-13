import SwiftUI

/// About / credits panel. Carries the required open-source attribution (AutoEq is MIT-licensed and
/// must be credited) plus version and acknowledgements.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var updates: AppUpdateChecker
    @Bindable var journey: ProductJourneyTracker

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
            Text("Sonance EQ").font(.title2.bold())
            HStack(spacing: 6) {
                Text(EQText.format("Version %@", version)).font(.caption).foregroundStyle(.secondary)
                Button {
                    Task { await updates.check(force: true) }
                } label: {
                    if updates.state == .checking {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(updates.state == .checking)
                .help("Check for Updates")
                .accessibilityLabel("Check for Updates")
            }
            Text("A system-wide, driverless equalizer for macOS.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

            updateStatus

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                credit("Headphone presets", "AutoEq · Jaakko Pasanen (MIT)",
                       url: "https://github.com/jaakkopasanen/AutoEq")
                credit("Purchases", "RevenueCat", url: "https://www.revenuecat.com")
                credit("App icon", "Generated with OpenAI image models")
                credit("EQ design", "RBJ Audio EQ Cookbook · Apple Accelerate (vDSP)")
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
            if journey.configured || journey.optedIn {
                Toggle("Share usage metrics", isOn: Binding(
                    get: { journey.optedIn },
                    set: { enabled in
                        journey.setConsent(enabled)
                        if enabled { journey.observeSession(); Task { await journey.flush() } }
                    }))
                    .font(.caption)
                Text("Help improve setup and purchases. Audio, names and email addresses are never included. Turn this off to clear unsent metrics.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
            }
            Text("© 2026 Isaiah Dupree").font(.caption2).foregroundStyle(.secondary)

            Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 360)
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updates.state {
        case .idle, .checking:
            EmptyView()
        case .upToDate:
            Label("Sonance EQ is up to date", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .updateAvailable(version):
            Button { updates.openAppStore() } label: {
                Label(EQText.format("Version %@ is available", version), systemImage: "arrow.down.circle.fill")
            }
            .controlSize(.small)
        case .failed:
            Text("Couldn’t check for updates. Try again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func credit(_ title: String, _ detail: String, url: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(LocalizedStringKey(title)).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            if let url, let link = URL(string: url) {
                Link(detail, destination: link)
            } else {
                Text(LocalizedStringKey(detail))
            }
            Spacer()
        }
    }
}
