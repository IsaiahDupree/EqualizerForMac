import SwiftUI

/// About / credits panel. Carries the required open-source attribution (AutoEq is MIT-licensed and
/// must be credited) plus version and acknowledgements, plus a language selector.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var localization = LocalizationManager()

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
            Text("app.title", bundle: .main).font(.title2.bold())
            Text("about.version", bundle: .main) + Text(" \(version)")
                .font(.caption).foregroundStyle(.secondary)
            Text("about.description", bundle: .main)
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                credit("about.credit.headphones", "about.credit.headphones.detail",
                       url: "https://github.com/jaakkopasanen/AutoEq")
                credit("about.credit.purchases", "about.credit.purchases.detail",
                       url: "https://www.revenuecat.com")
                credit("about.credit.icon", "about.credit.icon.detail")
                credit("about.credit.eqdesign", "about.credit.eqdesign.detail")
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            LanguageSelectorView(localization: localization)

            Divider()
            Text("about.copyright", bundle: .main).font(.caption2).foregroundStyle(.secondary)

            Button { dismiss() } label: {
                Text("button.close", bundle: .main)
            }.keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 360)
    }

    private func credit(_ titleKey: LocalizedStringKey, _ detailKey: LocalizedStringKey, url: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(titleKey, bundle: .main).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            if let url, let link = URL(string: url) {
                Link(destination: link) {
                    Text(detailKey, bundle: .main)
                }
            } else {
                Text(detailKey, bundle: .main)
            }
            Spacer()
        }
    }
}
