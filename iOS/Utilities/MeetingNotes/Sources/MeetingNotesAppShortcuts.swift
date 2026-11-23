import AppIntents
import Foundation

struct TranscribeLatestMeetingIntent: AppIntent {
    static var title: LocalizedStringResource = "Transcribe Latest Recording"
    static var description = IntentDescription("Transcribe the newest saved meeting recording using on-device speech recognition.")

    static var openAppWhenRun: Bool { true }

    #if compiler(>=6.4)
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }
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

struct DraftLatestMeetingSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Draft Latest Meeting Summary"
    static var description = IntentDescription(
        "Create an unsaved, on-device summary draft from the newest saved transcript and open it for review."
    )

    static var openAppWhenRun: Bool { true }

    #if compiler(>=6.4)
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = MeetingNotesStore.shared
        guard FoundationModelsMeetingSummarizer.isAvailable else {
            return .result(dialog: "On-device meeting summaries require iOS 27 and an available Apple language model.")
        }
        guard !store.isRecording, !store.isStartingRecording else {
            return .result(dialog: "Stop the active recording before preparing a saved meeting summary.")
        }
        guard store.transcribingID == nil else {
            return .result(dialog: "Wait for transcription to finish before preparing a summary.")
        }
        guard store.pendingShortcutSummaryDraft == nil else {
            return .result(dialog: "Review or discard the open summary draft in Clear Record first.")
        }
        guard let latest = store.sessions.first else {
            return .result(dialog: "Create and save a consented recording before requesting a summary.")
        }
        let transcriptSnapshot = latest.transcript
        guard !transcriptSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .result(dialog: "Transcribe the newest saved recording before requesting a summary.")
        }

        do {
            let summary = try await store.createSummaryDraft(
                for: latest,
                transcriptSnapshot: transcriptSnapshot
            )
            try Task.checkCancellation()
            guard store.stageShortcutSummaryDraft(
                for: latest,
                transcriptSnapshot: transcriptSnapshot,
                summary: summary
            ) else {
                return .result(dialog: "Clear Record could not stage this draft. Open the app to review the current transcript and any open draft.")
            }
            return .result(dialog: "A local summary draft is ready to review in Clear Record. It has not been saved.")
        } catch is CancellationError {
            return .result(dialog: "Summary drafting was cancelled. No summary was saved.")
        } catch {
            store.errorMessage = error.localizedDescription
            return .result(dialog: "Clear Record could not prepare the summary. Open the app to review the status.")
        }
    }
}

struct MeetingNotesAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        var shortcuts = [AppShortcut(
            intent: TranscribeLatestMeetingIntent(),
            phrases: [
                "Transcribe my latest recording in \(.applicationName)",
                "Transcribe the newest session in \(.applicationName)"
            ],
            shortTitle: "Transcribe Latest Recording",
            systemImageName: "waveform.and.text"
        )]
        if #available(iOS 27.0, *), FoundationModelsMeetingSummarizer.isAvailable {
            shortcuts.append(AppShortcut(
                intent: DraftLatestMeetingSummaryIntent(),
                phrases: [
                    "Draft a summary of my latest meeting in \(.applicationName)",
                    "Summarize my latest meeting with \(.applicationName)"
                ],
                shortTitle: "Draft Meeting Summary",
                systemImageName: "sparkles"
            ))
        }
        return shortcuts
    }
}
