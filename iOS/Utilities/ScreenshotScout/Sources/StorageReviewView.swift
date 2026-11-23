import Foundation
import SwiftUI

struct StorageReviewView: View {
    @EnvironmentObject private var library: ScreenshotLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot = LibraryStorageSnapshot.empty
    @State private var isLoading = true
    @State private var pendingRemoval: LibraryStorageEntry?
    @State private var activeSnapshotID = UUID()
    @State private var storageScan: Task<LibraryStorageSnapshot, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Local media copies", value: ByteCountFormatter.string(fromByteCount: snapshot.totalBytes, countStyle: .file))
                    LabeledContent("Images", value: "\(snapshot.imageCount) · \(formatted(snapshot.imageBytes))")
                    LabeledContent("Videos", value: "\(snapshot.videoCount) · \(formatted(snapshot.videoBytes))")
                    LabeledContent("Sampled video frames", value: formatted(snapshot.frameBytes))
                } header: {
                    Text("Screenshot Scout storage")
                } footer: {
                    Text("Sizes cover media tracked in Screenshot Scout: private copies of images, videos, and sampled frames. Removing one here does not remove the original from Photos.")
                }

                Section {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Measuring local copies…").foregroundStyle(.secondary)
                        }
                    } else if snapshot.entries.isEmpty {
                        ContentUnavailableView(
                            "No local media copies",
                            systemImage: "internaldrive",
                            description: Text("Images and videos you select from Photos will appear here.")
                        )
                    } else {
                        ForEach(snapshot.entries) { entry in
                            HStack(spacing: 12) {
                                Image(systemName: entry.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.title).font(.body.weight(.medium)).lineLimit(1)
                                    Text(entry.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(formatted(entry.byteCount))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    pendingRemoval = entry
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(entry.title) from Screenshot Scout")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                } header: {
                    Text("Largest copies first")
                } footer: {
                    Text("A video’s size includes its private video file and sampled frame images. Removal requires confirmation and affects only Screenshot Scout’s copies and index.")
                }

                if let error = library.errorMessage {
                    Section("Storage action status") {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Local storage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: library.searchRevision) {
                storageScan?.cancel()
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await refreshSnapshot()
            }
            .onDisappear { storageScan?.cancel() }
            .alert("Remove this local copy?", isPresented: removalConfirmationPresented) {
                Button("Cancel", role: .cancel) { pendingRemoval = nil }
                Button("Remove from Screenshot Scout", role: .destructive) {
                    removePendingEntry()
                }
            } message: {
                Text("This removes Screenshot Scout’s private copy and search entry. The original media in Photos stays untouched.")
            }
        }
    }

    private var removalConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
    }

    private func refreshSnapshot() async {
        let snapshotID = UUID()
        activeSnapshotID = snapshotID
        isLoading = true
        let imageFiles = library.images.map { image in
            (record: image, url: library.imageURL(for: image))
        }
        let videoFiles = library.videos.map { video in
            (
                record: video,
                url: library.videoURL(for: video),
                frameURLs: video.frames.map { library.frameURL(for: $0) }
            )
        }

        let scan = Task.detached(priority: .utility) {
            var entries: [LibraryStorageEntry] = []
            var imageBytes: Int64 = 0
            var videoBytes: Int64 = 0
            var frameBytes: Int64 = 0

            for item in imageFiles {
                guard !Task.isCancelled else { return LibraryStorageSnapshot.empty }
                let bytes = libraryFileByteCount(at: item.url)
                imageBytes += bytes
                entries.append(LibraryStorageEntry(
                    asset: .image(item.record),
                    byteCount: bytes,
                    title: storageImageTitle(item.record),
                    detail: "Image · Added \(item.record.importedAt.formatted(date: .abbreviated, time: .omitted))"
                ))
            }

            for item in videoFiles {
                guard !Task.isCancelled else { return LibraryStorageSnapshot.empty }
                let sourceBytes = libraryFileByteCount(at: item.url)
                let sampledFrameBytes = item.frameURLs.reduce(Int64.zero) { $0 + libraryFileByteCount(at: $1) }
                videoBytes += sourceBytes
                frameBytes += sampledFrameBytes
                entries.append(LibraryStorageEntry(
                    asset: .video(item.record),
                    byteCount: sourceBytes + sampledFrameBytes,
                    title: "Video · \(storageDuration(item.record.durationSeconds))",
                    detail: "Video and \(item.frameURLs.count) sampled frames · Added \(item.record.importedAt.formatted(date: .abbreviated, time: .omitted))"
                ))
            }

            entries.sort {
                if $0.byteCount != $1.byteCount { return $0.byteCount > $1.byteCount }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

            return LibraryStorageSnapshot(
                entries: entries,
                imageBytes: imageBytes,
                videoBytes: videoBytes,
                frameBytes: frameBytes,
                imageCount: imageFiles.count,
                videoCount: videoFiles.count
            )
        }
        storageScan = scan
        let updatedSnapshot = await scan.value
        guard activeSnapshotID == snapshotID, !Task.isCancelled else { return }
        snapshot = updatedSnapshot
        storageScan = nil
        isLoading = false
    }

    private func removePendingEntry() {
        guard let entry = pendingRemoval else { return }
        pendingRemoval = nil
        switch entry.asset {
        case .image(let image): library.remove(image)
        case .video(let video): library.remove(video)
        }
    }
}

private struct LibraryStorageSnapshot: Sendable {
    var entries: [LibraryStorageEntry]
    var imageBytes: Int64
    var videoBytes: Int64
    var frameBytes: Int64
    var imageCount: Int
    var videoCount: Int

    var totalBytes: Int64 { imageBytes + videoBytes + frameBytes }

    static let empty = LibraryStorageSnapshot(
        entries: [], imageBytes: 0, videoBytes: 0, frameBytes: 0, imageCount: 0, videoCount: 0
    )
}

private struct LibraryStorageEntry: Identifiable, Sendable {
    enum Asset: Sendable {
        case image(IndexedImage)
        case video(IndexedVideo)
    }

    let asset: Asset
    let byteCount: Int64
    let title: String
    let detail: String

    var id: String {
        switch asset {
        case .image(let image): "image:\(image.id.uuidString)"
        case .video(let video): "video:\(video.id.uuidString)"
        }
    }

    var systemImage: String {
        switch asset {
        case .image(_): "photo"
        case .video(_): "video"
        }
    }
}

private func libraryFileByteCount(at url: URL) -> Int64 {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? NSNumber else { return 0 }
    return max(size.int64Value, 0)
}

private func storageImageTitle(_ image: IndexedImage) -> String {
    guard let label = image.labels.first, !label.isEmpty else { return "Image" }
    return "Image · \(label.capitalized)"
}

private func storageDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "duration unavailable" }
    let totalSeconds = Int(min(seconds.rounded(), 359_999))
    return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
}
