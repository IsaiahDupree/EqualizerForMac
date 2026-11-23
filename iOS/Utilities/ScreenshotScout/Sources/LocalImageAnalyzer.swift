import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

enum LocalImageAnalyzer {
    static func process(_ data: Data) throws -> ProcessedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2200
                ] as CFDictionary
              ) else {
            throw LibraryError.unreadableImage
        }

        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw LibraryError.couldNotSave
        }
        CGImageDestinationAddImage(
            destination,
            thumbnail,
            [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { throw LibraryError.couldNotSave }

        let handler = VNImageRequestHandler(cgImage: thumbnail)
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false

        let classificationRequest = VNClassifyImageRequest()
        try handler.perform([textRequest, classificationRequest])

        let text = (textRequest.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        let labels = (classificationRequest.results ?? [])
            .filter { $0.confidence >= 0.12 }
            .prefix(5)
            .map(\.identifier)

        return ProcessedImage(jpegData: encoded as Data, recognizedText: text, labels: labels)
    }
}
