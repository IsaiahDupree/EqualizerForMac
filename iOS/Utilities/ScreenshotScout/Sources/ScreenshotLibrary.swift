import Combine
import CryptoKit
import Foundation
import PhotosUI
import SwiftUI

@MainActor
final class ScreenshotLibrary: ObservableObject {
    @Published private(set) var images: [IndexedImage] = []
    @Published private(set) var videos: [IndexedVideo] = []
    @Published private(set) var reviewQueue: [ReviewQueueEntry] = []
    @Published private(set) var isImporting = false
    @Published private(set) var isCancellingImageImport = false
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
    private var imageCancelRequested = false
    private var videoCancelRequested = false
    private var imageDigests = Set<String>()
    private var videoDigests = Set<String>()

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
    private var reviewQueueURL: URL { libraryDirectory.appendingPathComponent("review-queue.json") }

    init() {
        loadIndex()
        loadReviewQueue()
        do {
            try applyBackupExclusions()
        } catch {
            errorMessage = "Some Screenshot Scout files could not be marked for backup exclusion: \(error.localizedDescription)"
        }
    }

    func importItems(_ selections: [PhotosPickerItem]) async {
        guard !selections.isEmpty else { return }
        imageCancelRequested = false
        isCancellingImageImport = false
        isImporting = true
        errorMessage = nil
        statusMessage = nil
        var added = 0
        var duplicates = 0
        var cancelled = false

        for selection in selections {
            guard !imageCancelRequested else {
                cancelled = true
                break
            }
            var storedImageURL: URL?
            var insertedID: UUID?
            var insertedDigest: String?
            do {
                guard let data = try await selection.loadTransferable(type: Data.self),
                      !data.isEmpty else {
                    throw LibraryError.unreadableImage
                }
                guard !imageCancelRequested else {
                    cancelled = true
                    break
                }

                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard !imageDigests.contains(digest) else {
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
                storedImageURL = destination
                try markExcludedFromBackup(at: destination)

                let record = IndexedImage(
                    id: id,
                    fileName: fileName,
                    importedAt: Date(),
                    recognizedText: processed.recognizedText,
                    labels: processed.labels,
                    sha256: digest
                )
                images.insert(record, at: 0)
                imageDigests.insert(digest)
                insertedID = id
                insertedDigest = digest
                searchRevision &+= 1
                try saveIndex()
                added += 1
                storedImageURL = nil
                if imageCancelRequested {
                    cancelled = true
                    break
                }
            } catch {
                if let insertedID {
                    images.removeAll { $0.id == insertedID }
                    if let insertedDigest { imageDigests.remove(insertedDigest) }
                    searchRevision &+= 1
                    try? saveIndex()
                }
                if let storedImageURL { try? FileManager.default.removeItem(at: storedImageURL) }
                errorMessage = error.localizedDescription
            }
        }

        isImporting = false
        isCancellingImageImport = false
        imageCancelRequested = false
        let summary = "\(added) added · \(duplicates) exact duplicate\(duplicates == 1 ? "" : "s") skipped"
        statusMessage = cancelled ? "\(summary) · stopped early" : summary
    }

    func cancelImageImport() {
        guard isImporting, !isCancellingImageImport else { return }
        imageCancelRequested = true
        isCancellingImageImport = true
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
        let queryTerms = normalizedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        let imageSnapshot = images
        let videoSnapshot = videos
        let task = Task.detached(priority: .userInitiated) {
            var matchedImages: [IndexedImage] = []
            matchedImages.reserveCapacity(min(imageSnapshot.count, 100))
            for image in imageSnapshot {
                try Task.checkCancellation()
                if image.matches(searchTerms: queryTerms) {
                    matchedImages.append(image)
                }
            }

            var matchedVideos: [IndexedVideo] = []
            matchedVideos.reserveCapacity(min(videoSnapshot.count, 100))
            for video in videoSnapshot {
                try Task.checkCancellation()
                if video.matches(searchTerms: queryTerms) {
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
        let reviewQueueRecords = reviewQueue
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
                    recognizedText: includeRecognizedDetails ? item.recognizedText : nil,
                    sceneDescription: includeRecognizedDetails ? item.sceneDescription : nil
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
                            recognizedText: frame.recognizedText,
                            sceneDescription: frame.sceneDescription
                        )
                    } : nil
                )
            }
            let inventory = LibraryInventoryExport(
                schemaVersion: 4,
                exportedAt: Date(),
                images: exportedImages,
                videos: exportedVideos,
                reviewQueue: reviewQueueRecords
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
            try markExcludedFromBackup(at: videosDirectory)
            try markExcludedFromBackup(at: videoFramesDirectory)
        } catch {
            isImportingVideos = false
            errorMessage = error.localizedDescription
            return
        }

        for selection in selections {
            var storedVideoURL: URL?
            var storedFrameURLs: [URL] = []
            var insertedID: UUID?
            var insertedDigest: String?
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
                guard !videoDigests.contains(digest) else {
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
                try markExcludedFromBackup(at: destination)
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
                    try markExcludedFromBackup(at: frameURL)
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
                videoDigests.insert(digest)
                searchRevision &+= 1
                insertedID = id
                insertedDigest = digest
                try saveIndex()
                added += 1
            } catch {
                if let insertedID {
                    videos.removeAll { $0.id == insertedID }
                    if let insertedDigest { videoDigests.remove(insertedDigest) }
                    searchRevision &+= 1
                }
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

    func updateSceneDescription(for imageID: UUID, description: String?) throws {
        guard let index = images.firstIndex(where: { $0.id == imageID }) else {
            throw LibraryError.imageNoLongerAvailable
        }
        let normalized = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = normalized?.isEmpty == false ? normalized : nil
        guard images[index].sceneDescription != value else { return }

        let previous = images[index]
        images[index].sceneDescription = value
        do {
            try saveIndex()
            searchRevision &+= 1
        } catch {
            images[index] = previous
            throw error
        }
    }

    func updateSceneDescription(for videoID: UUID, frameIndex: Int, description: String?) throws {
        guard let videoPosition = videos.firstIndex(where: { $0.id == videoID }),
              let framePosition = videos[videoPosition].frames.firstIndex(where: { $0.index == frameIndex }) else {
            throw LibraryError.videoNoLongerAvailable
        }
        let normalized = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = normalized?.isEmpty == false ? normalized : nil
        guard videos[videoPosition].frames[framePosition].sceneDescription != value else { return }

        let previous = videos[videoPosition]
        videos[videoPosition].frames[framePosition].sceneDescription = value
        do {
            try saveIndex()
            searchRevision &+= 1
        } catch {
            videos[videoPosition] = previous
            throw error
        }
    }

    func isInReviewQueue(_ item: IndexedImage) -> Bool {
        reviewQueue.contains { $0.mediaKind == .image && $0.mediaID == item.id }
    }

    func isInReviewQueue(_ item: IndexedVideo) -> Bool {
        reviewQueue.contains { $0.mediaKind == .video && $0.mediaID == item.id }
    }

    func addToReviewQueue(_ item: IndexedImage) {
        addToReviewQueue(mediaKind: .image, mediaID: item.id)
    }

    func addToReviewQueue(_ item: IndexedVideo) {
        addToReviewQueue(mediaKind: .video, mediaID: item.id)
    }

    func toggleReviewQueue(_ item: IndexedImage) {
        if isInReviewQueue(item) {
            let previousQueue = reviewQueue
            reviewQueue.removeAll { $0.mediaKind == .image && $0.mediaID == item.id }
            do { try saveReviewQueue() }
            catch {
                reviewQueue = previousQueue
                errorMessage = error.localizedDescription
            }
        } else {
            addToReviewQueue(item)
        }
    }

    func toggleReviewQueue(_ item: IndexedVideo) {
        if isInReviewQueue(item) {
            let previousQueue = reviewQueue
            reviewQueue.removeAll { $0.mediaKind == .video && $0.mediaID == item.id }
            do { try saveReviewQueue() }
            catch {
                reviewQueue = previousQueue
                errorMessage = error.localizedDescription
            }
        } else {
            addToReviewQueue(item)
        }
    }

    func removeFromReviewQueue(_ entry: ReviewQueueEntry) {
        let previousQueue = reviewQueue
        reviewQueue.removeAll { $0.id == entry.id }
        do { try saveReviewQueue() }
        catch {
            reviewQueue = previousQueue
            errorMessage = error.localizedDescription
        }
    }

    private func addToReviewQueue(mediaKind: ReviewQueueMediaKind, mediaID: UUID) {
        guard !reviewQueue.contains(where: { $0.mediaKind == mediaKind && $0.mediaID == mediaID }) else { return }
        reviewQueue.insert(ReviewQueueEntry(mediaKind: mediaKind, mediaID: mediaID, queuedAt: Date()), at: 0)
        do { try saveReviewQueue() }
        catch {
            reviewQueue.removeAll { $0.mediaKind == mediaKind && $0.mediaID == mediaID }
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ item: IndexedImage) {
        if similarityTargetID == item.id { cancelSimilaritySearch() }
        let previousImages = images
        let previousReviewQueue = reviewQueue
        let previousDigests = imageDigests
        let previousSearchRevision = searchRevision
        let url = imageURL(for: item)
        images.removeAll { $0.id == item.id }
        imageDigests.remove(item.sha256)
        reviewQueue.removeAll { $0.mediaKind == .image && $0.mediaID == item.id }
        searchRevision &+= 1
        do { try saveLibraryState() }
        catch {
            images = previousImages
            reviewQueue = previousReviewQueue
            imageDigests = previousDigests
            searchRevision = previousSearchRevision
            errorMessage = error.localizedDescription
            return
        }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            errorMessage = "The image was removed from the index, but its private copy could not be deleted: \(error.localizedDescription)"
        }
    }

    func remove(_ item: IndexedVideo) {
        let previousVideos = videos
        let previousReviewQueue = reviewQueue
        let previousDigests = videoDigests
        let previousSearchRevision = searchRevision
        videos.removeAll { $0.id == item.id }
        videoDigests.remove(item.sha256)
        reviewQueue.removeAll { $0.mediaKind == .video && $0.mediaID == item.id }
        searchRevision &+= 1
        do { try saveLibraryState() }
        catch {
            videos = previousVideos
            reviewQueue = previousReviewQueue
            videoDigests = previousDigests
            searchRevision = previousSearchRevision
            errorMessage = error.localizedDescription
            return
        }

        do {
            for frame in item.frames {
                let url = frameURL(for: frame)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            let url = videoURL(for: item)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        } catch {
            errorMessage = "The video was removed from the index, but its private copy or sampled frames could not be deleted: \(error.localizedDescription)"
        }
    }

    private func loadIndex() {
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? decoder.decode([IndexedImage].self, from: data) {
            images = saved.filter { FileManager.default.fileExists(atPath: imageURL(for: $0).path) }
        }
        imageDigests = Set(images.map(\.sha256))

        if let videoData = try? Data(contentsOf: videoIndexURL),
           let savedVideos = try? decoder.decode([IndexedVideo].self, from: videoData) {
            videos = savedVideos.filter { video in
                FileManager.default.fileExists(atPath: videoURL(for: video).path)
                    && video.frames.allSatisfy { FileManager.default.fileExists(atPath: frameURL(for: $0).path) }
            }
        }
        videoDigests = Set(videos.map(\.sha256))
    }

    private func saveIndex() throws {
        try prepareLocalLibrary()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let imageData = try encoder.encode(images)
        let videoData = try encoder.encode(videos)
        try writeIndexFiles([(indexURL, imageData), (videoIndexURL, videoData)])
    }

    private func loadReviewQueue() {
        guard let data = try? Data(contentsOf: reviewQueueURL),
              let saved = try? decoder.decode([ReviewQueueEntry].self, from: data) else { return }
        reviewQueue = saved.filter { entry in
            switch entry.mediaKind {
            case .image: images.contains { $0.id == entry.mediaID }
            case .video: videos.contains { $0.id == entry.mediaID }
            }
        }
        if reviewQueue.count != saved.count { try? saveReviewQueue() }
    }

    private func saveReviewQueue() throws {
        try prepareLocalLibrary()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let queueData = try encoder.encode(reviewQueue)
        try writeIndexFiles([(reviewQueueURL, queueData)])
    }

    private func saveLibraryState() throws {
        try prepareLocalLibrary()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let imageData = try encoder.encode(images)
        let videoData = try encoder.encode(videos)
        let queueData = try encoder.encode(reviewQueue)
        try writeIndexFiles([
            (indexURL, imageData),
            (videoIndexURL, videoData),
            (reviewQueueURL, queueData)
        ])
    }

    private func writeIndexFiles(_ updates: [(URL, Data)]) throws {
        let fileManager = FileManager.default
        let previous = try updates.map { update -> (URL, Data?) in
            let url = update.0
            let data: Data?
            if fileManager.fileExists(atPath: url.path) {
                data = try Data(contentsOf: url)
            } else {
                data = nil
            }
            return (url, data)
        }

        do {
            for (url, data) in updates {
                try data.write(to: url, options: .atomic)
                try markExcludedFromBackup(at: url)
            }
        } catch {
            let saveError = error
            var rollbackFailures: [String] = []
            for (url, data) in previous.reversed() {
                if let data {
                    do {
                        try data.write(to: url, options: .atomic)
                        try markExcludedFromBackup(at: url)
                    } catch {
                        rollbackFailures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                } else if fileManager.fileExists(atPath: url.path) {
                    do { try fileManager.removeItem(at: url) }
                    catch { rollbackFailures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                }
            }
            guard !rollbackFailures.isEmpty else { throw saveError }
            throw LibraryPersistenceError.rollbackFailed(
                save: saveError.localizedDescription,
                rollback: rollbackFailures.joined(separator: "; ")
            )
        }
    }

    private func prepareLocalLibrary() throws {
        try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        try markExcludedFromBackup(at: libraryDirectory)
    }

    private func applyBackupExclusions() throws {
        try prepareLocalLibrary()
        for image in images {
            try markExcludedFromBackup(at: imageURL(for: image))
        }
        for video in videos {
            try markExcludedFromBackup(at: videoURL(for: video))
            for frame in video.frames {
                try markExcludedFromBackup(at: frameURL(for: frame))
            }
        }
        for directory in [videosDirectory, videoFramesDirectory]
        where FileManager.default.fileExists(atPath: directory.path) {
            try markExcludedFromBackup(at: directory)
        }
        for url in [indexURL, videoIndexURL, reviewQueueURL]
        where FileManager.default.fileExists(atPath: url.path) {
            try markExcludedFromBackup(at: url)
        }
    }

    private func markExcludedFromBackup(at url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var localURL = url
        try localURL.setResourceValues(values)
    }
}

private enum LibraryPersistenceError: LocalizedError {
    case rollbackFailed(save: String, rollback: String)

    var errorDescription: String? {
        switch self {
        case .rollbackFailed(let save, let rollback):
            "Screenshot Scout could not save its library (\(save)) or restore the previous index data (\(rollback)). The on-disk index may not match the previous state."
        }
    }
}
