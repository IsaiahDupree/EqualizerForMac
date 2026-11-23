import Combine
import CryptoKit
import Foundation
import PhotosUI
import SwiftUI

@MainActor
final class ScreenshotLibrary: ObservableObject {
    @Published private(set) var images: [IndexedImage] = []
    @Published private(set) var isImporting = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var libraryDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenshotScout", isDirectory: true)
    }

    private var indexURL: URL { libraryDirectory.appendingPathComponent("index.json") }

    init() {
        loadIndex()
    }

    func importItems(_ selections: [PhotosPickerItem]) async {
        guard !selections.isEmpty else { return }
        isImporting = true
        statusMessage = nil
        var added = 0
        var duplicates = 0

        for selection in selections {
            do {
                guard let data = try await selection.loadTransferable(type: Data.self),
                      !data.isEmpty else {
                    throw LibraryError.unreadableImage
                }

                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard !images.contains(where: { $0.sha256 == digest }) else {
                    duplicates += 1
                    continue
                }

                let processed = try await Task.detached(priority: .userInitiated) {
                    try LocalImageAnalyzer.process(data)
                }.value

                try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
                let id = UUID()
                let fileName = "\(id.uuidString).jpg"
                let destination = libraryDirectory.appendingPathComponent(fileName)
                try processed.jpegData.write(to: destination, options: .atomic)

                let record = IndexedImage(
                    id: id,
                    fileName: fileName,
                    importedAt: Date(),
                    recognizedText: processed.recognizedText,
                    labels: processed.labels,
                    sha256: digest
                )
                images.insert(record, at: 0)
                added += 1
                try saveIndex()
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        isImporting = false
        statusMessage = "\(added) added · \(duplicates) exact duplicate\(duplicates == 1 ? "" : "s") skipped"
    }

    func imageURL(for item: IndexedImage) -> URL {
        libraryDirectory.appendingPathComponent(item.fileName)
    }

    func remove(_ item: IndexedImage) {
        let url = imageURL(for: item)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            images.removeAll { $0.id == item.id }
            try saveIndex()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let saved = try? decoder.decode([IndexedImage].self, from: data) else { return }
        images = saved.filter { FileManager.default.fileExists(atPath: imageURL(for: $0).path) }
    }

    private func saveIndex() throws {
        try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(images).write(to: indexURL, options: .atomic)
    }
}
