import Foundation

enum PracticePlaybackRate: Float, CaseIterable {
    case half = 0.5
    case threeQuarters = 0.75
    case nineTenths = 0.9
    case normal = 1.0

    var title: String {
        String(format: "%.2g×", Double(rawValue))
    }
}

struct PracticeTrack: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    let storedFilename: String
    let importedAt: Date
    let duration: TimeInterval
    var markers: [PracticeMarker]
    var analysis: MusicAnalysis?
    var loops: [PracticeLoop] = []

    private enum CodingKeys: String, CodingKey {
        case id, title, storedFilename, importedAt, duration, markers, analysis, loops
    }

    init(
        id: UUID,
        title: String,
        storedFilename: String,
        importedAt: Date,
        duration: TimeInterval,
        markers: [PracticeMarker],
        analysis: MusicAnalysis?,
        loops: [PracticeLoop] = []
    ) {
        self.id = id
        self.title = title
        self.storedFilename = storedFilename
        self.importedAt = importedAt
        self.duration = duration
        self.markers = markers
        self.analysis = analysis
        self.loops = loops
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        storedFilename = try values.decode(String.self, forKey: .storedFilename)
        importedAt = try values.decode(Date.self, forKey: .importedAt)
        duration = try values.decode(TimeInterval.self, forKey: .duration)
        markers = try values.decodeIfPresent([PracticeMarker].self, forKey: .markers) ?? []
        analysis = try values.decodeIfPresent(MusicAnalysis.self, forKey: .analysis)
        loops = try values.decodeIfPresent([PracticeLoop].self, forKey: .loops) ?? []
    }
}

struct PracticeLibraryDocument: Codable, Sendable {
    var schemaVersion: Int
    var tracks: [PracticeTrack]
    var selectedTrackID: UUID?

    init(tracks: [PracticeTrack], selectedTrackID: UUID?) {
        schemaVersion = 1
        self.tracks = tracks
        self.selectedTrackID = selectedTrackID
    }
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

struct PracticeLoop: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var startSeconds: TimeInterval
    var endSeconds: TimeInterval

    init(title: String, startSeconds: TimeInterval, endSeconds: TimeInterval) {
        id = UUID()
        self.title = title
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

struct MusicAnalysis: Codable, Sendable {
    var tempoBPM: Int?
    var keySpans: [KeySpan]
    var sectionSpans: [TimeSpan]
    var paceSpans: [PaceSpan]
    var instrumentSpans: [InstrumentSpan]?
    var integratedLoudnessLUFS: Double?
    var peakDecibels: Double?

    var firstKeySpan: KeySpan? {
        keySpans.min { $0.startSeconds < $1.startSeconds }
    }
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

struct InstrumentSpan: Codable, Sendable, Identifiable {
    var id: String { "\(instrument)-\(startSeconds)-\(durationSeconds)" }
    var instrument: String
    var startSeconds: TimeInterval
    var durationSeconds: TimeInterval
}

enum TrackStudyError: LocalizedError {
    case invalidAudioFile
    case audioFileMissing
    case unsupportedLibraryVersion
    case musicUnderstandingRequiresCurrentSDK
    case musicUnderstandingRequiresIOS27

    var errorDescription: String? {
        switch self {
        case .invalidAudioFile:
            "This file does not contain a readable audio track."
        case .audioFileMissing:
            "The saved audio file is missing. Import the track again to continue."
        case .unsupportedLibraryVersion:
            "This Track Study library was saved by a newer app version. Update Track Study before changing its contents."
        case .musicUnderstandingRequiresCurrentSDK:
            "Music analysis requires an iOS 27 SDK. This build still supports playback and practice markers."
        case .musicUnderstandingRequiresIOS27:
            "Music analysis requires iOS 27 or later. Playback and practice markers remain available."
        }
    }
}
