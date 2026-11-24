import SwiftUI

@main
struct SonanceEQRouteInstallerApp: App {
    var body: some Scene {
        WindowGroup {
            RouteInstallerView()
        }
    }
}

private struct RouteInstallerView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.tint)
            Text("Sonance EQ Routing")
                .font(.title2.weight(.semibold))
            Text("Open Sonance EQ, then choose Sonance EQ as the audio output in Control Center.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
