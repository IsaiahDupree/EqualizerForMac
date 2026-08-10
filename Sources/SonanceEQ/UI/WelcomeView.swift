import SwiftUI

/// First-run welcome sheet: what Sonance EQ actually does (system-wide, driverless, tap-based EQ)
/// and the one-time permission it needs, before the user lands on the dense main editor.
struct WelcomeView: View {
    @Bindable var app: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Welcome to Sonance EQ").font(.title2.bold())
                Text("A system-wide equalizer for your whole Mac — no driver, no reboot.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                point("waveform.path.ecg", "Shapes every app's audio",
                      "Sonance EQ reads system audio straight from Core Audio and re-injects it after "
                      + "shaping — nothing installs at the OS level. DRM-protected streams (some Apple "
                      + "Music/Netflix playback) pass through un-equalized.")
                point("lock.shield", "One-time permission",
                      "macOS will ask for Audio Capture access the first time you press Start. Sonance EQ "
                      + "only reads audio to equalize it — it never records or sends anything anywhere "
                      + "unless you explicitly start the Recorder.")
                point("headphones", "Presets tuned for your gear",
                      "Start from a built-in preset, save your own, or search 8,850+ headphone-specific "
                      + "corrections from the AutoEq library.")
                point("app.badge", "Per-app control (Pro)",
                      "Pro unlocks per-app EQ targeting, an independent volume/output mixer, and a "
                      + "system audio recorder.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Get Started") {
                app.onboarding.complete()
                if app.permission.status == .unknown {
                    app.permission.request { _ in }
                }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 420)
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
