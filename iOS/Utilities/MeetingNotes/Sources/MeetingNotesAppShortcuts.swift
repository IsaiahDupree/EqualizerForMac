import AppIntents
import Foundation

struct TranscribeLatestMeetingIntent: AppIntent {
    static var title: LocalizedStringResource = "Transcribe Latest Recording"
    static var description = IntentDescription("Transcribe the newest saved meeting recording using on-device speech recognition.")

    #if compiler(>=6.4)
    static var supportedModes: IntentModes { .foreground(.immediate) }
    #else
    static var openAppWhenRun: Bool { true }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = MeetingNotesStore.shared
        guard !store.isRecording, !store.isStartingRecording else {
            return .result(dialog: "Stop the active recording before transcribing a saved session.")
        }
        guard store.transcribingID == nil else {
            return .result(dialog: "A session is already being transcribed.")
        }
        guard let latest = store.sessions.first else {
            return .result(dialog: "Create a consented recording before requesting a transcript.")
        }
        guard latest.transcript.isEmpty else {
            return .result(dialog: "The newest session already has a transcript. Edit or share it in Clear Record.")
        }

        let localeIdentifier = UserDefaults.standard.string(
            forKey: "clearRecord.transcriptionLocaleIdentifier"
        ) ?? "en-US"
        await store.transcribe(latest, localeIdentifier: localeIdentifier)

        guard let updated = store.sessions.first(where: { $0.id == latest.id }),
              !updated.transcript.isEmpty else {
            return .result(dialog: "On-device transcription did not complete. Open Clear Record to review the status.")
        }
        return .result(dialog: "Transcript saved on this device. Review it in Clear Record.")
    }
}

struct MeetingNotesAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranscribeLatestMeetingIntent(),
            phrases: [
                "Transcribe my latest recording in \(.applicationName)",
                "Transcribe the newest session in \(.applicationName)"
            ],
            shortTitle: "Transcribe Latest Recording",
            systemImageName: "waveform.and.text"
        )
    }
}
