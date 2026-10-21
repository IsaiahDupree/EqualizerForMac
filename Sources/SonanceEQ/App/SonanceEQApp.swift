import SwiftUI
import StoreKit

/// Unified subsystem string for os.Logger across the app.
let kSubsystem = "com.isaiahdupree.SonanceEQ"

@main
struct SonanceEQApp: App {
    @State private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    var body: some Scene {
        Window("Sonance EQ", id: "main") {
            ContentView(app: app)
                .task { app.review.present = { requestReview() } }
                .task {
                    app.journey.observeSession()
                    await app.journey.flush()
                }
                .onOpenURL { url in
                    if app.journey.receive(url) { Task { await app.journey.flush() } }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await app.license.refresh() } }
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {} // no "New Window"
            CommandGroup(replacing: .appInfo) {
                Button("About Sonance EQ") { app.showingAbout = true }
            }
        }
    }
}
