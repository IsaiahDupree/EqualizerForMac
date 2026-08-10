import SwiftUI
import StoreKit

/// Unified subsystem string for os.Logger across the app.
let kSubsystem = "com.isaiahdupree.SonanceEQ"

@main
struct SonanceEQApp: App {
    @State private var app = AppState()
    @State private var localization = LocalizationManager()
    @Environment(\.requestReview) private var requestReview

    var body: some Scene {
        Window("Sonance EQ", id: "main") {
            ContentView(app: app)
                .environment(\.locale, localization.locale)
                .task { app.review.present = { requestReview() } }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {} // no "New Window"
            CommandGroup(replacing: .appInfo) {
                Button { app.showingAbout = true } label: {
                    Text("button.about", bundle: .main)
                }
            }
        }
    }
}
