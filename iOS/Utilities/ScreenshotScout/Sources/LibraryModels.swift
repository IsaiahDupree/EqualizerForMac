import Foundation

struct IndexedImage: Identifiable, Codable, Hashable {
    var id: UUID
    var fileName: String
    var importedAt: Date
    var recognizedText: String
    var labels: [String]
    var sha256: String
}

struct ProcessedImage: Sendable {
    var jpegData: Data
    var recognizedText: String
    var labels: [String]
}

enum LibraryError: LocalizedError, Sendable {
    case unreadableImage
    case couldNotSave

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "This item could not be read as an image."
        case .couldNotSave: "Screenshot Scout could not save this image locally."
        }
    }
}
