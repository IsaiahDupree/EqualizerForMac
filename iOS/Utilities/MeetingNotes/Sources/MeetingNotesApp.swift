import SwiftUI

@main
struct MeetingNotesApp: App {
    @State private var store = MeetingNotesStore()

    var body: some Scene {
        WindowGroup {
            MeetingLibraryView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}
