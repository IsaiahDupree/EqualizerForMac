import SwiftUI

/// About / credits panel. Carries the required open-source attribution (AutoEq is MIT-licensed and
/// must be credited) plus version and acknowledgements.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

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
            Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
            Text("A system-wide, driverless equalizer for macOS.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

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
            Text("© 2026 Isaiah Dupree").font(.caption2).foregroundStyle(.secondary)

            Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 360)
    }

    private func credit(_ title: String, _ detail: String, url: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            if let url, let link = URL(string: url) {
                Link(detail, destination: link)
            } else {
                Text(detail)
            }
            Spacer()
        }
    }
}
