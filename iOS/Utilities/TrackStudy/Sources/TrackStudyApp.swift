import SwiftUI

@main
struct TrackStudyApp: App {
    @StateObject private var store = TrackStudyStore.shared

    init() {
        TrackStudyAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            TrackStudyView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
