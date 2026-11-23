import AppIntents
import Foundation

struct AddTrackStudyMarkerIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Practice Point"
    static var description = IntentDescription("Save a practice marker at the current Track Study playhead.")

    #if compiler(>=6.4)
    static var supportedModes: IntentModes { .foreground(.immediate) }
    #else
    static var openAppWhenRun: Bool { true }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TrackStudyStore.shared
        guard store.track != nil else {
            return .result(dialog: "Import an audio file in Track Study before saving a practice point.")
        }
        let seconds = store.currentTime
        store.addMarker(title: "Siri marker", at: seconds)
        return .result(dialog: "Practice marker saved at \(Self.timeString(seconds)).")
    }

    private static func timeString(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }
}

struct TrackStudyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTrackStudyMarkerIntent(),
            phrases: [
                "Mark this point in \(.applicationName)",
                "Add a practice marker in \(.applicationName)"
            ],
            shortTitle: "Mark Practice Point",
            systemImageName: "bookmark"
        )
    }
}
