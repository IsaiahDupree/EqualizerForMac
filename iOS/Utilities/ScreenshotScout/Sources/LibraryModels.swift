import Foundation

struct IndexedImage: Identifiable, Codable, Hashable {
    var id: UUID
    var fileName: String
    var importedAt: Date
    var recognizedText: String
    var labels: [String]
    var sha256: String
}

struct IndexedVideo: Identifiable, Codable, Hashable {
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

struct IndexedVideoFrame: Codable, Hashable, Identifiable {
    var index: Int
    var fileName: String
    var timeSeconds: Double
    var recognizedText: String
    var labels: [String]
    var id: Int { index }
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

enum LibraryError: LocalizedError, Sendable {
    case unreadableImage
    case couldNotSave
    case unreadableVideo
    case noVideoFrames

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "This item could not be read as an image."
        case .couldNotSave: "Screenshot Scout could not save this image locally."
        case .unreadableVideo: "This video could not be opened. Try selecting a different video."
        case .noVideoFrames: "Screenshot Scout could not read any frames from this video."
        }
    }
}
