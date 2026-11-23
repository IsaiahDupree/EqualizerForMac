import Foundation

struct MeetingSession: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var audioFileName: String
    var transcript: String
}

enum MeetingNotesError: LocalizedError {
    case consentRequired
    case microphoneDenied
    case speechDenied
    case onDeviceRecognitionUnavailable
    case speechServiceUnavailable
    case recordingCouldNotStart
    case recordingNotFound

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
        }
    }
}
