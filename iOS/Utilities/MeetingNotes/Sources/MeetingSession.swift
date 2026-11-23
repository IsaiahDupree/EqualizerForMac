import Foundation

struct MeetingSession: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var audioFileName: String
    var transcript: String
    var aiSummary: String?
    var summarySourceDigest: String?
}

struct MeetingSummaryDraft: Identifiable, Equatable {
    let sessionID: UUID
    let sessionTitle: String
    let transcriptSnapshot: String
    let summary: String

    var id: UUID { sessionID }
}

enum MeetingNotesError: LocalizedError {
    case consentRequired
    case microphoneDenied
    case speechDenied
    case onDeviceRecognitionUnavailable
    case speechServiceUnavailable
    case recordingCouldNotStart
    case recordingNotFound
    case playbackCouldNotStart
    case summaryAlreadyInProgress
    case summaryReviewAlreadyOpen
    case summaryTranscriptChanged
    case summaryRequiresTranscript

    var errorDescription: String? {
        switch self {
        case .consentRequired:
            "Confirm that everyone present has agreed before recording."
        case .microphoneDenied:
            "Microphone access is required to record a session."
        case .speechDenied:
            "Speech Recognition access is required to transcribe on this device."
        case .onDeviceRecognitionUnavailable:
            "On-device recognition is unavailable for this language on this device. The recording is saved; no audio was sent for transcription."
        case .speechServiceUnavailable:
            "On-device speech recognition is temporarily unavailable. The recording is saved; try transcribing it again later."
        case .recordingCouldNotStart:
            "The recording could not start. Check microphone access and try again."
        case .recordingNotFound:
            "This saved recording could not be found."
        case .playbackCouldNotStart:
            "The saved recording could not be played. Try sharing the audio file to check that it is available."
        case .summaryAlreadyInProgress:
            "A summary draft is already being prepared. Wait for it to finish before starting another."
        case .summaryReviewAlreadyOpen:
            "Review or discard the current summary draft before preparing another one."
        case .summaryTranscriptChanged:
            "The transcript changed while the summary was being prepared. Generate a fresh draft."
        case .summaryRequiresTranscript:
            "Transcribe the saved recording before creating a summary."
        }
    }
}
