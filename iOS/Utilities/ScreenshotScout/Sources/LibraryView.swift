import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    private enum MediaKind: String, CaseIterable {
        case images = "Images"
        case videos = "Videos"
    }

    @EnvironmentObject private var library: ScreenshotLibrary
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var searchText = ""
    @State private var mediaKind: MediaKind = .images
    @State private var presentedSheet: LibraryPresentation?
    @State private var inventoryDocument: InventoryExportDocument?
    @State private var isExportingInventory = false
    @State private var isPreparingInventoryExport = false

    private let columns = [GridItem(.adaptive(minimum: 165), spacing: 14)]

    private var normalizedSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchTaskID: String {
        "\(normalizedSearchQuery)|\(library.searchRevision)"
    }

    private var filteredImages: [IndexedImage] {
        guard !normalizedSearchQuery.isEmpty else { return library.images }
        guard library.searchResults?.query == normalizedSearchQuery else { return [] }
        return library.searchResults?.images ?? []
    }

    private var filteredVideos: [IndexedVideo] {
        guard !normalizedSearchQuery.isEmpty else { return library.videos }
        guard library.searchResults?.query == normalizedSearchQuery else { return [] }
        return library.searchResults?.videos ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    searchField
                    Picker("Media type", selection: $mediaKind) {
                        ForEach(MediaKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    if mediaKind == .images {
                        if library.images.isEmpty { emptyState } else { libraryGrid }
                    } else {
                        if library.videos.isEmpty { emptyVideoState } else { videoGrid }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .background(Color(red: 0.055, green: 0.065, blue: 0.09).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $presentedSheet) { presentation in
                switch presentation {
                case .image(let item):
                    ImageDetailView(item: item)
                        .environmentObject(library)
                        .presentationDragIndicator(.visible)
                case .video(let item):
                    VideoDetailView(item: item)
                        .environmentObject(library)
                        .presentationDragIndicator(.visible)
                case .reviewQueue:
                    ReviewQueueView()
                        .environmentObject(library)
                        .presentationDragIndicator(.visible)
                }
            }
            .fileExporter(
                isPresented: $isExportingInventory,
                document: inventoryDocument,
                contentType: .json,
                defaultFilename: "Screenshot-Scout-Inventory"
            ) { result in
                if case .failure(let error) = result {
                    library.errorMessage = error.localizedDescription
                }
                inventoryDocument = nil
            }
            .onChange(of: selectedItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await library.importItems(newItems)
                    selectedItems = []
                }
            }
            .onChange(of: selectedVideoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await library.importVideoItems(newItems)
                    selectedVideoItems = []
                }
            }
            .task(id: searchTaskID) {
                if !normalizedSearchQuery.isEmpty {
                    do { try await Task.sleep(for: .milliseconds(180)) }
                    catch { return }
                    guard !Task.isCancelled else { return }
                }
                await library.search(query: normalizedSearchQuery)
            }
            .onDisappear { library.cancelSearch() }
            .alert("Could not process selected media", isPresented: errorPresented) {
                Button("OK", role: .cancel) { library.errorMessage = nil }
            } message: {
                Text(library.errorMessage ?? "Please try selecting the image again.")
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SCREENSHOT SCOUT")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(2.1)
                        .foregroundStyle(Color.cyan.opacity(0.9))
                    Text("Your media,\nfindable again.")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                Image(systemName: "viewfinder")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color.cyan)
                    .frame(width: 72, height: 72)
                    .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
            }

            HStack(spacing: 10) {
                stat(value: "\(library.images.count)", title: "IMAGES")
                Rectangle().fill(.white.opacity(0.13)).frame(width: 1, height: 30)
                stat(value: "\(library.videos.count)", title: "VIDEOS")
                Spacer()
                if mediaKind == .images {
                    PhotosPicker(selection: $selectedItems, maxSelectionCount: 40, matching: .images) {
                        Label("Add images", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.03, green: 0.10, blue: 0.13))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.cyan, in: Capsule())
                    }
                    .disabled(library.isImporting || library.isImportingVideos)
                } else {
                    PhotosPicker(selection: $selectedVideoItems, maxSelectionCount: 8, matching: .videos) {
                        Label("Add videos", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.03, green: 0.10, blue: 0.13))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.cyan, in: Capsule())
                    }
                    .disabled(library.isImporting || library.isImportingVideos)
                }
            }

            HStack {
                Menu {
                    Button("Metadata only") { prepareInventoryExport(includeRecognizedDetails: false) }
                    Button("Include recognized text and labels") {
                        prepareInventoryExport(includeRecognizedDetails: true)
                    }
                } label: {
                    Label(isPreparingInventoryExport ? "Preparing…" : "Export inventory", systemImage: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                .disabled(
                    isPreparingInventoryExport
                        || library.isImporting
                        || library.isImportingVideos
                        || (library.images.isEmpty && library.videos.isEmpty)
                )

                Spacer(minLength: 8)
                Text("JSON index only · no media copies")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
            }

            Button { presentedSheet = .reviewQueue } label: {
                Label("Review queue · \(library.reviewQueue.count)", systemImage: "tray.full")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

            if library.isImporting {
                HStack(spacing: 10) {
                    ProgressView().tint(.cyan)
                    Text(library.isCancellingImageImport
                         ? "Stopping after the current image…"
                         : "Reading text and image details on this device…")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 0)
                    Button(library.isCancellingImageImport ? "Stopping…" : "Stop") {
                        library.cancelImageImport()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .disabled(library.isCancellingImageImport)
                }
            } else if library.isImportingVideos {
                HStack(spacing: 10) {
                    ProgressView().tint(.cyan)
                    Text("Finding text and scenes in selected videos on this device…")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 0)
                    Button("Cancel") { library.cancelVideoImport() }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.cyan)
                }
            } else if let message = library.statusMessage {
                Text(message).font(.footnote).foregroundStyle(.cyan.opacity(0.9))
            }
        }
        .padding(20)
        .background(
            LinearGradient(colors: [Color(red: 0.10, green: 0.16, blue: 0.23), Color(red: 0.09, green: 0.11, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private func stat(value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(title).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(.white.opacity(0.5))
        }
    }

    private var searchField: some View {
        HStack(spacing: 11) {
            if library.isSearching {
                ProgressView().tint(.cyan)
            } else {
                Image(systemName: "magnifyingglass").foregroundStyle(.cyan)
            }
            TextField("Search words, scenes, or labels", text: $searchText)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private var libraryGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(searchText.isEmpty ? "YOUR IMAGE LIBRARY" : "IMAGE SEARCH RESULTS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.58))
                Spacer()
                Text("\(filteredImages.count) ITEMS")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.38))
            }

            if filteredImages.isEmpty {
                if library.isSearching {
                    ProgressView("Searching your image index…")
                        .tint(.cyan)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                } else {
                    ContentUnavailableView.search(text: searchText)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 20)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filteredImages) { item in
                        Button { presentedSheet = .image(item) } label: { ImageCard(item: item, url: library.imageURL(for: item)) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.cyan.opacity(0.85))
                .frame(width: 76, height: 76)
                .background(.cyan.opacity(0.1), in: Circle())
            Text("Start with a few screenshots")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Choose screenshots or photos to recognize their text, group visual labels, and search your private library.")
                .font(.system(size: 14, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.58))
                .frame(maxWidth: 310)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 22)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24))
    }

    private var videoGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(searchText.isEmpty ? "YOUR VIDEO LIBRARY" : "VIDEO SEARCH RESULTS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.58))
                Spacer()
                Text("\(filteredVideos.count) ITEMS")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.38))
            }

            if filteredVideos.isEmpty {
                if library.isSearching {
                    ProgressView("Searching your video index…")
                        .tint(.cyan)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                } else {
                    ContentUnavailableView.search(text: searchText)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 20)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filteredVideos) { item in
                        Button { presentedSheet = .video(item) } label: {
                            VideoCard(item: item, thumbnailURL: item.frames.first.map { library.frameURL(for: $0) })
                        }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyVideoState: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.cyan.opacity(0.85))
                .frame(width: 76, height: 76)
                .background(.cyan.opacity(0.1), in: Circle())
            Text("Find a moment inside your videos")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Select videos to scan a few frames for visible text and scene labels. Search results point to the video and sampled moments for your review.")
                .font(.system(size: 14, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.58))
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 22)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24))
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })
    }

    private func prepareInventoryExport(includeRecognizedDetails: Bool) {
        guard !isPreparingInventoryExport else { return }
        isPreparingInventoryExport = true
        Task {
            do {
                let data = try await library.makeInventoryExport(
                    includeRecognizedDetails: includeRecognizedDetails
                )
                inventoryDocument = InventoryExportDocument(data: data)
                isExportingInventory = true
            } catch {
                library.errorMessage = error.localizedDescription
            }
            isPreparingInventoryExport = false
        }
    }
}

private enum LibraryPresentation: Identifiable {
    case image(IndexedImage)
    case video(IndexedVideo)
    case reviewQueue

    var id: String {
        switch self {
        case .image(let item): "image:\(item.id.uuidString)"
        case .video(let item): "video:\(item.id.uuidString)"
        case .reviewQueue: "review-queue"
        }
    }
}

private struct InventoryExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct ImageCard: View {
    let item: IndexedImage
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.white.opacity(0.06))
                        .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.3)))
                }
            }
            .frame(height: 142)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text(item.labels.prefix(2).joined(separator: " · ").capitalized.isEmpty ? "Image" : item.labels.prefix(2).joined(separator: " · ").capitalized)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(item.recognizedText.isEmpty ? "No visible text" : item.recognizedText.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 11, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.white.opacity(0.56))
                Text(item.importedAt.formatted(date: .abbreviated, time: .omitted).uppercased())
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.cyan.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(Color(red: 0.105, green: 0.12, blue: 0.16), in: RoundedRectangle(cornerRadius: 17))
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}
