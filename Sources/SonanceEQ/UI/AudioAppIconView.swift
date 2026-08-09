import SwiftUI

/// Shared rendering for an `AudioApp`'s icon in the per-app pickers (App Mixer row, per-app EQ target
/// menu, Recorder source menu) — a real app icon rather than the raw Core Audio bundle ID text those
/// pickers used to fall back to for apps `NSRunningApplication` couldn't name.
struct AudioAppIconView: View {
    let audioApp: AudioApp
    var size: CGFloat = 16

    var body: some View {
        if let icon = audioApp.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}
