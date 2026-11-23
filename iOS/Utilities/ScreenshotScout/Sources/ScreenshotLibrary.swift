import Combine
import CryptoKit
import Foundation
import PhotosUI
import SwiftUI

@MainActor
final class ScreenshotLibrary: ObservableObject {
    @Published private(set) var images: [IndexedImage] = []
    @Published private(set) var videos: [IndexedVideo] = []
    @Published private(set) var isImporting = false
    @Published private(set) var isImportingVideos = false
    @Published private(set) var isFindingSimilar = false
    @Published private(set) var similarityTargetID: UUID?
    @Published private(set) var similarMatches: [SimilarityMatch] = []
    @Published private(set) var searchResults: LibrarySearchResults?
    @Published private(set) var isSearching = false
    @Published private(set) var searchRevision = 0
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var similarityTask: Task<[SimilarityMatch], Error>?
    private var searchTask: Task<LibrarySearchResults, Error>?
    private var activeSearchID = UUID()
    private var videoHashTask: Task<String, Error>?
    private var videoAnalysisTask: Task<ProcessedVideo, Error>?
    private var videoCancelRequested = false

    private var libraryDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenshotScout", isDirectory: true)
    }

    private var videosDirectory: URL {
        libraryDirectory.appendingPathComponent("Videos", isDirectory: true)
    }

    private var videoFramesDirectory: URL {
        libraryDirectory.appendingPathComponent("VideoFrames", isDirectory: true)
    }

    private var indexURL: URL { libraryDirectory.appendingPathComponent("index.json") }
    private var videoIndexURL: URL { libraryDirectory.appendingPathComponent("videos.json") }

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

                try prepareLocalLibrary()
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
                searchRevision &+= 1
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

    func videoURL(for item: IndexedVideo) -> URL {
        videosDirectory.appendingPathComponent(item.fileName)
    }

    func frameURL(for frame: IndexedVideoFrame) -> URL {
        videoFramesDirectory.appendingPathComponent(frame.fileName)
    }

    func search(query: String) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            cancelSearch()
            searchResults = nil
            return
        }

        searchTask?.cancel()
        let searchID = UUID()
        activeSearchID = searchID
        isSearching = true
        let imageSnapshot = images
        let videoSnapshot = videos
        let task = Task.detached(priority: .userInitiated) {
            var matchedImages: [IndexedImage] = []
            matchedImages.reserveCapacity(min(imageSnapshot.count, 100))
            for image in imageSnapshot {
                try Task.checkCancellation()
                let searchable = ([image.recognizedText] + image.labels).joined(separator: " ")
                if searchable.localizedCaseInsensitiveContains(normalizedQuery) {
                    matchedImages.append(image)
                }
            }

            var matchedVideos: [IndexedVideo] = []
            matchedVideos.reserveCapacity(min(videoSnapshot.count, 100))
            for video in videoSnapshot {
                try Task.checkCancellation()
                let searchable = ([video.recognizedText] + video.labels).joined(separator: " ")
                if searchable.localizedCaseInsensitiveContains(normalizedQuery) {
                    matchedVideos.append(video)
                }
            }
            return LibrarySearchResults(
                query: normalizedQuery,
                images: matchedImages,
                videos: matchedVideos
            )
        }
        searchTask = task

        do {
            let result = try await task.value
            guard activeSearchID == searchID else { return }
            searchResults = result
        } catch is CancellationError {
            return
        } catch {
            guard activeSearchID == searchID else { return }
            errorMessage = error.localizedDescription
        }
        if activeSearchID == searchID {
            searchTask = nil
            isSearching = false
        }
    }

    func cancelSearch() {
        activeSearchID = UUID()
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    func makeInventoryExport(includeRecognizedDetails: Bool) async throws -> Data {
        let imageRecords = images
        let videoRecords = videos
        let libraryDirectory = libraryDirectory

        return try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            func byteCount(at url: URL) -> Int64? {
                guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                      let size = attributes[.size] as? NSNumber else { return nil }
                return size.int64Value
            }

            let exportedImages = imageRecords.map { item in
                InventoryImageRecord(
                    id: item.id,
                    importedAt: item.importedAt,
                    byteCount: byteCount(at: libraryDirectory.appendingPathComponent(item.fileName)),
                    sha256: item.sha256,
                    labels: includeRecognizedDetails ? item.labels : nil,
                    recognizedText: includeRecognizedDetails ? item.recognizedText : nil
                )
            }
            let exportedVideos = videoRecords.map { item in
                InventoryVideoRecord(
                    id: item.id,
                    importedAt: item.importedAt,
                    durationSeconds: item.durationSeconds,
                    byteCount: item.byteCount,
                    sha256: item.sha256,
                    frameCount: item.frames.count,
                    labels: includeRecognizedDetails ? item.labels : nil,
                    recognizedText: includeRecognizedDetails ? item.recognizedText : nil,
                    frames: includeRecognizedDetails ? item.frames.map { frame in
                        InventoryVideoFrameRecord(
                            index: frame.index,
                            timeSeconds: frame.timeSeconds,
                            labels: frame.labels,
                            recognizedText: frame.recognizedText
                        )
                    } : nil
                )
            }
            let inventory = LibraryInventoryExport(
                schemaVersion: 1,
                exportedAt: Date(),
                images: exportedImages,
                videos: exportedVideos
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(inventory)
        }.value
    }

    func importVideoItems(_ selections: [PhotosPickerItem]) async {
        guard !selections.isEmpty else { return }
        isImportingVideos = true
        videoCancelRequested = false
        errorMessage = nil
        statusMessage = nil
        var added = 0
        var duplicates = 0
        var cancelled = false

        do {
            try prepareLocalLibrary()
            try FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: videoFramesDirectory, withIntermediateDirectories: true)
        } catch {
            isImportingVideos = false
            errorMessage = error.localizedDescription
            return
        }

        for selection in selections {
            var storedVideoURL: URL?
            var storedFrameURLs: [URL] = []
            var insertedID: UUID?
            do {
                guard let imported = try await selection.loadTransferable(type: ImportedVideo.self) else {
                    throw LibraryError.unreadableVideo
                }
                defer { try? FileManager.default.removeItem(at: imported.url) }
                guard !videoCancelRequested else { throw CancellationError() }

                let hashTask = Task.detached(priority: .utility) {
                    try LocalVideoAnalyzer.sha256(url: imported.url)
                }
                videoHashTask = hashTask
                let digest = try await hashTask.value
                videoHashTask = nil
                guard !videoCancelRequested else { throw CancellationError() }
                guard !videos.contains(where: { $0.sha256 == digest }) else {
                    duplicates += 1
                    continue
                }

                let id = UUID()
                let suffix = imported.url.pathExtension.isEmpty ? "mov" : imported.url.pathExtension.lowercased()
                let destination = videosDirectory.appendingPathComponent(id.uuidString).appendingPathExtension(suffix)
                try await Task.detached(priority: .utility) {
                    try FileManager.default.copyItem(at: imported.url, to: destination)
                }.value
                storedVideoURL = destination
                guard !videoCancelRequested else { throw CancellationError() }

                let analysisTask = Task.detached(priority: .utility) {
                    try await LocalVideoAnalyzer.process(url: destination)
                }
                videoAnalysisTask = analysisTask
                let processed = try await analysisTask.value
                videoAnalysisTask = nil
                var indexedFrames: [IndexedVideoFrame] = []
                for (index, frame) in processed.frames.enumerated() {
                    guard !videoCancelRequested else { throw CancellationError() }
                    let fileName = "\(id.uuidString)-\(index).jpg"
                    let frameURL = videoFramesDirectory.appendingPathComponent(fileName)
                    try frame.jpegData.write(to: frameURL, options: .atomic)
                    storedFrameURLs.append(frameURL)
                    indexedFrames.append(
                        IndexedVideoFrame(
                            index: index,
                            fileName: fileName,
                            timeSeconds: frame.timeSeconds,
                            recognizedText: frame.recognizedText,
                            labels: frame.labels
                        )
                    )
                }

                let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                let record = IndexedVideo(
                    id: id,
                    fileName: destination.lastPathComponent,
                    importedAt: Date(),
                    durationSeconds: processed.durationSeconds,
                    byteCount: byteCount,
                    sha256: digest,
                    frames: indexedFrames
                )
                videos.insert(record, at: 0)
                searchRevision &+= 1
                insertedID = id
                try saveIndex()
                added += 1
            } catch {
                if let insertedID { videos.removeAll { $0.id == insertedID } }
                for url in storedFrameURLs { try? FileManager.default.removeItem(at: url) }
                if let storedVideoURL { try? FileManager.default.removeItem(at: storedVideoURL) }
                if error is CancellationError || videoCancelRequested {
                    cancelled = true
                    break
                }
                errorMessage = error.localizedDescription
            }
        }

        videoHashTask = nil
        videoAnalysisTask = nil
        isImportingVideos = false
        statusMessage = cancelled
            ? "Video indexing cancelled · \(added) saved · \(duplicates) duplicates skipped"
            : "\(added) video\(added == 1 ? "" : "s") indexed · \(duplicates) exact duplicate\(duplicates == 1 ? "" : "s") skipped"
    }

    func cancelVideoImport() {
        videoCancelRequested = true
        videoHashTask?.cancel()
        videoAnalysisTask?.cancel()
    }

    func findSimilar(to item: IndexedImage) async {
        guard !isFindingSimilar else { return }
        isFindingSimilar = true
        similarityTargetID = item.id
        similarMatches = []
        errorMessage = nil

        let targetURL = imageURL(for: item)
        let candidates = images
            .filter { $0.id != item.id }
            .map { SimilarityCandidate(id: $0.id, url: imageURL(for: $0)) }

        do {
            let task = Task.detached(priority: .utility) {
                try LocalImageAnalyzer.rankSimilar(to: targetURL, candidates: candidates)
            }
            similarityTask = task
            let matches = try await task.value
            similarMatches = Array(matches.prefix(12))
        } catch is CancellationError {
            similarMatches = []
        } catch {
            errorMessage = error.localizedDescription
        }

        similarityTask = nil
        isFindingSimilar = false
    }

    func cancelSimilaritySearch() {
        similarityTask?.cancel()
    }

    func remove(_ item: IndexedImage) {
        if similarityTargetID == item.id { cancelSimilaritySearch() }
        let url = imageURL(for: item)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            images.removeAll { $0.id == item.id }
            searchRevision &+= 1
            try saveIndex()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ item: IndexedVideo) {
        do {
            for frame in item.frames {
                let url = frameURL(for: frame)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            let url = videoURL(for: item)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            videos.removeAll { $0.id == item.id }
            searchRevision &+= 1
            try saveIndex()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadIndex() {
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? decoder.decode([IndexedImage].self, from: data) {
            images = saved.filter { FileManager.default.fileExists(atPath: imageURL(for: $0).path) }
        }

        if let videoData = try? Data(contentsOf: videoIndexURL),
           let savedVideos = try? decoder.decode([IndexedVideo].self, from: videoData) {
            videos = savedVideos.filter { video in
                FileManager.default.fileExists(atPath: videoURL(for: video).path)
                    && video.frames.allSatisfy { FileManager.default.fileExists(atPath: frameURL(for: $0).path) }
            }
        }
    }

    private func saveIndex() throws {
        try prepareLocalLibrary()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(images).write(to: indexURL, options: .atomic)
        try encoder.encode(videos).write(to: videoIndexURL, options: .atomic)
    }

    private func prepareLocalLibrary() throws {
        try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = libraryDirectory
        try directory.setResourceValues(values)
    }
}
