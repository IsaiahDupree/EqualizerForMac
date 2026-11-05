import SwiftUI

public struct AnalyticsSettingsView: View {
    @ObservedObject private var analytics: ProductAnalytics
    @State private var feature: SonanceFeature
    @State private var reason = FeatureFeedback.worksWell

    public init(app: SonanceApp) {
        self.analytics = .shared(for: app)
        self._feature = State(initialValue: app.features.first(where: { $0 != .appOpen }) ?? .appOpen)
    }
    public var body: some View {
        Form {
            Section("Optional usage sharing") {
                Toggle("Share anonymous feature use", isOn: Binding(
                    get: { analytics.sharingEnabled }, set: { analytics.setSharingEnabled($0) }))
                Text("Help improve \(analytics.app.title) by sharing which features you use and whether an action succeeds or gets blocked. Sharing starts only when you turn it on. Turning it off stops sending and removes unsent observations.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("We receive feature identifiers, outcomes, app/build version, platform, time, and an anonymous identifier for this app installation. We do not send your audio, transcripts, diagrams, room measurements, filenames, device or app names, or search text. No advertising or session replay.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Tell us about a feature") {
                Picker("Feature", selection: $feature) {
                    ForEach(analytics.app.features.filter { $0 != .appOpen }) { Text($0.title).tag($0) }
                }
                Picker("Your experience", selection: $reason) {
                    ForEach(FeatureFeedback.allCases) { Text($0.title).tag($0) }
                }
                Text("Submit sends only the choices above and app/build details. This works with usage sharing off; that feedback gets a fresh identifier.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Submit Feedback") { analytics.submitFeedback(feature: feature, reason: reason) }
                    .disabled(!analytics.isAvailable)
                if !analytics.isAvailable {
                    Text("Feedback delivery is unavailable in this build.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !analytics.deliveryStatus.isEmpty || analytics.pendingCount > 0 {
                Section("Sending status") {
                    Text(analytics.deliveryStatus).font(.caption)
                    if analytics.pendingCount > 0 { Button("Retry Sending") { analytics.retry() } }
                }
            }
            Link("Privacy policy", destination: URL(string: "https://isaiahdupree.github.io/sonance-apps/privacy/")!)
        }
        .formStyle(.grouped)
        .task { analytics.retry() }
        .navigationTitle("Feedback & Analytics")
    }
}

/// Embed in an existing settings page or menu footer; it opens the same controls in every app.
public struct AnalyticsFeedbackButton: View {
    private let app: SonanceApp
    @State private var presented = false
    public init(app: SonanceApp) { self.app = app }
    public var body: some View {
        Button { presented = true } label: { Label("Feedback & Analytics", systemImage: "bubble.left.and.text.bubble.right") }
            .sheet(isPresented: $presented) {
                NavigationStack {
                    AnalyticsSettingsView(app: app)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { presented = false } } }
                }
#if os(macOS)
                .frame(width: 540, height: 620)
#endif
            }
    }
}
