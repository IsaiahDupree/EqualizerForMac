import SwiftUI

@main
struct ScreenshotScoutApp: App {
    @StateObject private var library = ScreenshotLibrary()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .preferredColorScheme(.dark)
        }
    }
}
