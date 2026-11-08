import AppKit
import SwiftUI
import StoreKit

/// Unified subsystem string for os.Logger across the app.
let kSubsystem = "com.isaiahdupree.SonanceEQ"

private enum SonanceWindow {
    static let main = "main"
}

@main
struct SonanceEQApp: App {
    @State private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    var body: some Scene {
        Window("Sonance EQ", id: SonanceWindow.main) {
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
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .commands {
            CommandGroup(replacing: .newItem) {} // no "New Window"
            CommandGroup(replacing: .appInfo) {
                Button("About Sonance EQ") { app.showingAbout = true }
            }
        }

        // AppState stays owned by the App, including while the main window is closed.
        // This menu only presents the existing controls; it never changes audio routing.
        MenuBarExtra("Sonance EQ", systemImage: "slider.horizontal.3") {
            MenuBarAccessMenu()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarAccessMenu: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Sonance EQ") {
            openWindow(id: SonanceWindow.main)
            // Keyboard menu tracking restores the previous app as it closes.
            // Request activation after that tracking action has returned.
            DispatchQueue.main.async { NSApplication.shared.activate() }
        }
        Divider()
        Button("Quit Sonance EQ") { NSApplication.shared.terminate(nil) }
    }
}
