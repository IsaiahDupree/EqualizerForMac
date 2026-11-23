import SwiftUI

@main
struct TrackStudyApp: App {
    @StateObject private var store = TrackStudyStore()

    var body: some Scene {
        WindowGroup {
            TrackStudyView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
