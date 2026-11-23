import SwiftUI

struct ImageDetailView: View {
    @EnvironmentObject private var library: ScreenshotLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemoval = false
    @State private var selectedSimilar: IndexedImage?

    let item: IndexedImage

    private var image: UIImage? { UIImage(contentsOfFile: library.imageURL(for: item).path) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("IMAGE LABELS", symbol: "sparkles")
                        if item.labels.isEmpty {
                            Text("No confident labels found.").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            FlowLabels(labels: item.labels)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("RECOGNIZED TEXT", symbol: "text.viewfinder")
                        if item.recognizedText.isEmpty {
                            Text("No visible text was found in this image.").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text(item.recognizedText)
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))

                    similarImages(for: item)

                    Text("Imported \(item.importedAt.formatted(date: .long, time: .shortened)). This is a private copy inside Screenshot Scout.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Image details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !item.recognizedText.isEmpty {
                            ShareLink(item: item.recognizedText) { Label("Share recognized text", systemImage: "square.and.arrow.up") }
                        }
                        Button(role: .destructive) { confirmRemoval = true } label: {
                            Label("Remove local copy", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Remove this image from Screenshot Scout?", isPresented: $confirmRemoval, titleVisibility: .visible) {
                Button("Remove local copy", role: .destructive) {
                    library.remove(item)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes only the private copy and its search data from Screenshot Scout. The original stays in Photos.")
            }
            .sheet(item: $selectedSimilar) { match in
                ImageDetailView(item: match)
                    .environmentObject(library)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private func similarImages(for item: IndexedImage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("CLOSEST IMAGES", symbol: "square.on.square")
                Spacer()
                if library.isFindingSimilar && library.similarityTargetID == item.id {
                    Button("Cancel") { library.cancelSimilaritySearch() }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.cyan)
                } else {
                    Button {
                        Task { await library.findSimilar(to: item) }
                    } label: {
                        Text(library.similarityTargetID == item.id ? "Refresh" : "Find")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.cyan)
                    }
                    .disabled(library.isFindingSimilar || library.images.count < 2)
                }
            }

            Text("Vision ranks local images by visual similarity. Review each suggestion yourself; none are removed automatically.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)

            if library.similarityTargetID == item.id {
                if library.isFindingSimilar {
                    HStack(spacing: 9) {
                        ProgressView().tint(.cyan)
                        Text("Comparing selected images on this device…")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if library.similarMatches.isEmpty {
                    Text("No other indexed images are available to compare.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 11) {
                            ForEach(0..<library.similarMatches.count, id: \.self) { index in
                                let result = library.similarMatches[index]
                                if let match = library.images.first(where: { $0.id == result.assetID }) {
                                    Button { selectedSimilar = match } label: {
                                        ClosestImageCard(item: match, url: library.imageURL(for: match), rank: index + 1)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(.secondary)
    }
}

private struct ClosestImageCard: View {
    let item: IndexedImage
    let url: URL
    let rank: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.secondary.opacity(0.2))
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }
            }
            .frame(width: 118, height: 92)
            .clipped()
            Text("Suggestion \(rank)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(width: 118, alignment: .leading)
    }
}

private struct FlowLabels: View {
    let labels: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(labels, id: \.self) { label in
                Text(label.capitalized)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Color.cyan.opacity(0.13), in: Capsule())
                    .foregroundStyle(Color.cyan)
            }
        }
    }
}
