import SwiftUI

/// Unified subsystem string for os.Logger across the app.
let kSubsystem = "com.isaiahdupree.SonanceEQ"

@main
struct SonanceEQApp: App {
    @State private var app = AppState()

    var body: some Scene {
        Window("Sonance EQ", id: "main") {
            ContentView(app: app)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {} // no "New Window"
        }
    }
}
