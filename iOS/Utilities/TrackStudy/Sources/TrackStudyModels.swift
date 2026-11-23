import Foundation

struct PracticeTrack: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    let storedFilename: String
    let importedAt: Date
    let duration: TimeInterval
    var markers: [PracticeMarker]
    var analysis: MusicAnalysis?
}

struct PracticeMarker: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    let seconds: TimeInterval

    init(title: String, seconds: TimeInterval) {
        id = UUID()
        self.title = title
        self.seconds = seconds
    }
}

struct MusicAnalysis: Codable, Sendable {
    var tempoBPM: Int?
    var keySpans: [KeySpan]
    var sectionSpans: [TimeSpan]
    var paceSpans: [PaceSpan]
}

struct KeySpan: Codable, Sendable, Identifiable {
    var id: String { "\(key)-\(startSeconds)" }
    var key: String
    var startSeconds: TimeInterval
    var durationSeconds: TimeInterval
}

struct TimeSpan: Codable, Sendable, Identifiable {
    var id: String { "\(startSeconds)-\(durationSeconds)" }
    var startSeconds: TimeInterval
    var durationSeconds: TimeInterval
}

struct PaceSpan: Codable, Sendable, Identifiable {
    var id: String { "\(startSeconds)-\(pace)" }
    var startSeconds: TimeInterval
    var durationSeconds: TimeInterval
    var pace: Double
}

enum TrackStudyError: LocalizedError {
    case invalidAudioFile
    case audioFileMissing
    case musicUnderstandingRequiresCurrentSDK
    case musicUnderstandingRequiresIOS27

    var errorDescription: String? {
        switch self {
        case .invalidAudioFile:
            "This file does not contain a readable audio track."
        case .audioFileMissing:
            "The saved audio file is missing. Import the track again to continue."
        case .musicUnderstandingRequiresCurrentSDK:
            "Music analysis requires an iOS 27 SDK. This build still supports playback and practice markers."
        case .musicUnderstandingRequiresIOS27:
            "Music analysis requires iOS 27 or later. Playback and practice markers remain available."
        }
    }
}
