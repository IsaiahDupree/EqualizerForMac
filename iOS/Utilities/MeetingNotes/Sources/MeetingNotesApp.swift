import SwiftUI

@main
struct MeetingNotesApp: App {
    @State private var store = MeetingNotesStore.shared

    init() {
        MeetingNotesAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            MeetingLibraryView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}
