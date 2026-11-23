import SwiftUI
import UIKit

struct ReviewQueueView: View {
    @EnvironmentObject private var library: ScreenshotLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMedia: ReviewQueuePresentation?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if library.reviewQueue.isEmpty {
                    ContentUnavailableView(
                        "Your review queue is empty",
                        systemImage: "tray",
                        description: Text("Open an image or video and add it here for later review.")
                    )
                } else {
                    List {
                        Section {
                            HStack(spacing: 9) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField("Search queued images and videos", text: $searchText)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("Search review queue by text, labels, or descriptions")
                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Clear review queue search")
                                }
                            }

                            if visibleEntries.isEmpty {
                                ContentUnavailableView(
                                    "No queued items match",
                                    systemImage: "magnifyingglass",
                                    description: Text("Try other words from the image or sampled video details.")
                                )
                                .listRowBackground(Color.clear)
                            }

                            ForEach(visibleEntries) { entry in
                                if entry.mediaKind == .image,
                                   let item = library.images.first(where: { $0.id == entry.mediaID }) {
                                    imageRow(item, entry: entry)
                                } else if entry.mediaKind == .video,
                                          let item = library.videos.first(where: { $0.id == entry.mediaID }) {
                                    videoRow(item, entry: entry)
                                }
                            }
                        } header: {
                            Text("\(visibleEntries.count) OF \(library.reviewQueue.count) · Open an item to review it; removing it here keeps its media in your library.")
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .navigationTitle("Review queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedMedia) { presentation in
                switch presentation {
                case .image(let item):
                    ImageDetailView(item: item)
                        .environmentObject(library)
                        .presentationDragIndicator(.visible)
                case .video(let item):
                    VideoDetailView(item: item)
                        .environmentObject(library)
                        .presentationDragIndicator(.visible)
                }
            }
            .alert("Could not update review queue", isPresented: errorPresented) {
                Button("OK", role: .cancel) { library.errorMessage = nil }
            } message: {
                Text(library.errorMessage ?? "Try again.")
            }
        }
    }

    private var visibleEntries: [ReviewQueueEntry] {
        let terms = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return library.reviewQueue }

        return library.reviewQueue.filter { entry in
            let searchableValues: [String]
            if entry.mediaKind == .image,
               let item = library.images.first(where: { $0.id == entry.mediaID }) {
                searchableValues = [item.recognizedText, item.sceneDescription ?? ""] + item.labels
            } else if entry.mediaKind == .video,
                      let item = library.videos.first(where: { $0.id == entry.mediaID }) {
                searchableValues = [item.recognizedText, item.sceneDescriptions] + item.labels
            } else {
                return false
            }

            return terms.allSatisfy { term in
                searchableValues.contains { $0.localizedStandardContains(term) }
            }
        }
    }

    private func imageRow(_ item: IndexedImage, entry: ReviewQueueEntry) -> some View {
        Button { selectedMedia = .image(item) } label: {
            HStack(spacing: 13) {
                thumbnail(url: library.imageURL(for: item))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.labels.prefix(2).joined(separator: " · ").capitalized.isEmpty
                         ? "Image"
                         : item.labels.prefix(2).joined(separator: " · ").capitalized)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(item.recognizedText.replacingOccurrences(of: "\n", with: " ").isEmpty
                         ? "No visible text"
                         : item.recognizedText.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    queuedLabel(entry.queuedAt)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        .swipeActions(edge: .trailing) {
            Button { library.removeFromReviewQueue(entry) } label: {
                Label("Reviewed", systemImage: "checkmark")
            }
            .tint(.cyan)
        }
    }

    private func videoRow(_ item: IndexedVideo, entry: ReviewQueueEntry) -> some View {
        Button { selectedMedia = .video(item) } label: {
            HStack(spacing: 13) {
                if let frame = item.frames.first {
                    thumbnail(url: library.frameURL(for: frame))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(.black.opacity(0.72), in: Circle())
                                .padding(4)
                        }
                } else {
                    thumbnail(url: nil)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.labels.prefix(2).joined(separator: " · ").capitalized.isEmpty
                         ? "Video"
                         : item.labels.prefix(2).joined(separator: " · ").capitalized)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(item.recognizedText.replacingOccurrences(of: "\n", with: " ").isEmpty
                         ? "No visible text in sampled moments"
                         : item.recognizedText.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    queuedLabel(entry.queuedAt)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        .swipeActions(edge: .trailing) {
            Button { library.removeFromReviewQueue(entry) } label: {
                Label("Reviewed", systemImage: "checkmark")
            }
            .tint(.cyan)
        }
    }

    private func thumbnail(url: URL?) -> some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color.cyan.opacity(0.12))
                    .overlay(Image(systemName: "photo").foregroundStyle(.cyan))
            }
        }
        .frame(width: 72, height: 66)
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    private func queuedLabel(_ date: Date) -> some View {
        Text("Added \(date.formatted(date: .abbreviated, time: .shortened))")
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })
    }
}

private enum ReviewQueuePresentation: Identifiable {
    case image(IndexedImage)
    case video(IndexedVideo)

    var id: String {
        switch self {
        case .image(let item): "image:\(item.id.uuidString)"
        case .video(let item): "video:\(item.id.uuidString)"
        }
    }
}
