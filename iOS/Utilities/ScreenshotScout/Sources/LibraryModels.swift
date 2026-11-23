import Foundation

struct IndexedImage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var fileName: String
    var importedAt: Date
    var recognizedText: String
    var labels: [String]
    var sha256: String
    var sceneDescription: String? = nil
}

struct IndexedVideo: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var fileName: String
    var importedAt: Date
    var durationSeconds: Double
    var byteCount: Int64
    var sha256: String
    var frames: [IndexedVideoFrame]

    var recognizedText: String {
        frames.map(\.recognizedText).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var labels: [String] {
        Array(Set(frames.flatMap(\.labels))).sorted()
    }
}

struct IndexedVideoFrame: Codable, Hashable, Identifiable, Sendable {
    var index: Int
    var fileName: String
    var timeSeconds: Double
    var recognizedText: String
    var labels: [String]
    var id: Int { index }
}

enum ReviewQueueMediaKind: String, Codable, Hashable, Sendable {
    case image
    case video
}

struct ReviewQueueEntry: Codable, Hashable, Identifiable, Sendable {
    var mediaKind: ReviewQueueMediaKind
    var mediaID: UUID
    var queuedAt: Date

    var id: String { "\(mediaKind.rawValue):\(mediaID.uuidString)" }
}

struct ProcessedImage: Sendable {
    var jpegData: Data
    var recognizedText: String
    var labels: [String]
}

struct SimilarityCandidate: Sendable {
    var id: UUID
    var url: URL
}

struct SimilarityMatch: Identifiable, Sendable {
    var assetID: UUID
    var distance: Float
    var id: UUID { assetID }
}

struct LibrarySearchResults: Sendable {
    var query: String
    var images: [IndexedImage]
    var videos: [IndexedVideo]
}

struct ProcessedVideo: Sendable {
    var durationSeconds: Double
    var frames: [ProcessedVideoFrame]
}

struct ProcessedVideoFrame: Sendable {
    var timeSeconds: Double
    var jpegData: Data
    var recognizedText: String
    var labels: [String]
}

struct LibraryInventoryExport: Codable, Sendable {
    var schemaVersion: Int
    var exportedAt: Date
    var images: [InventoryImageRecord]
    var videos: [InventoryVideoRecord]
    var reviewQueue: [ReviewQueueEntry]
}

struct InventoryImageRecord: Codable, Sendable {
    var id: UUID
    var importedAt: Date
    var byteCount: Int64?
    var sha256: String
    var labels: [String]?
    var recognizedText: String?
    var sceneDescription: String?
}

struct InventoryVideoRecord: Codable, Sendable {
    var id: UUID
    var importedAt: Date
    var durationSeconds: Double
    var byteCount: Int64
    var sha256: String
    var frameCount: Int
    var labels: [String]?
    var recognizedText: String?
    var frames: [InventoryVideoFrameRecord]?
}

struct InventoryVideoFrameRecord: Codable, Sendable {
    var index: Int
    var timeSeconds: Double
    var labels: [String]
    var recognizedText: String
}

enum LibraryError: LocalizedError, Sendable {
    case unreadableImage
    case imageNoLongerAvailable
    case couldNotSave
    case unreadableVideo
    case noVideoFrames

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "This item could not be read as an image."
        case .imageNoLongerAvailable: "This image is no longer in the Screenshot Scout library."
        case .couldNotSave: "Screenshot Scout could not save this image locally."
        case .unreadableVideo: "This video could not be opened. Try selecting a different video."
        case .noVideoFrames: "Screenshot Scout could not read any frames from this video."
        }
    }
}
