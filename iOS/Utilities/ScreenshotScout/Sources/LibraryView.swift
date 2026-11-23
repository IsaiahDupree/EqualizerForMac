import PhotosUI
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: ScreenshotLibrary
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var searchText = ""
    @State private var selectedImage: IndexedImage?

    private let columns = [GridItem(.adaptive(minimum: 165), spacing: 14)]

    private var filteredImages: [IndexedImage] {
        guard !searchText.isEmpty else { return library.images }
        return library.images.filter {
            $0.recognizedText.localizedCaseInsensitiveContains(searchText)
                || $0.labels.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    searchField
                    if library.images.isEmpty {
                        emptyState
                    } else {
                        libraryGrid
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .background(Color(red: 0.055, green: 0.065, blue: 0.09).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedImage) { item in
                ImageDetailView(item: item)
                    .environmentObject(library)
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: selectedItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await library.importItems(newItems)
                    selectedItems = []
                }
            }
            .alert("Could not process image", isPresented: errorPresented) {
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
                    Text("Your images,\nfindable again.")
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
                stat(value: "\(library.images.count)", title: "INDEXED")
                Rectangle().fill(.white.opacity(0.13)).frame(width: 1, height: 30)
                stat(value: library.images.reduce(0) { $0 + ($1.recognizedText.isEmpty ? 0 : 1) }.description, title: "WITH TEXT")
                Spacer()
                PhotosPicker(selection: $selectedItems, maxSelectionCount: 40, matching: .images) {
                    Label("Add images", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.03, green: 0.10, blue: 0.13))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.cyan, in: Capsule())
                }
                .disabled(library.isImporting)
            }

            if library.isImporting {
                HStack(spacing: 10) {
                    ProgressView().tint(.cyan)
                    Text("Reading text and image details on this device…")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
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
            Image(systemName: "magnifyingglass").foregroundStyle(.cyan)
            TextField("Search words or image labels", text: $searchText)
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
                Text(searchText.isEmpty ? "YOUR LIBRARY" : "SEARCH RESULTS")
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
                ContentUnavailableView.search(text: searchText)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 20)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filteredImages) { item in
                        Button { selectedImage = item } label: { ImageCard(item: item, url: library.imageURL(for: item)) }
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
            Text("Choose images to recognize their text, group useful visual labels, and search your own private library.")
                .font(.system(size: 14, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.58))
                .frame(maxWidth: 310)
            PhotosPicker(selection: $selectedItems, maxSelectionCount: 40, matching: .images) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.03, green: 0.10, blue: 0.13))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.cyan, in: Capsule())
            }
            .disabled(library.isImporting)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 22)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24))
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })
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
