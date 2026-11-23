import AVKit
import SwiftUI

struct VideoDetailView: View {
    @EnvironmentObject private var library: ScreenshotLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var confirmRemoval = false
    @State private var selectedFrame: IndexedVideoFrame?

    let item: IndexedVideo

    private var currentItem: IndexedVideo {
        library.videos.first(where: { $0.id == item.id }) ?? item
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Group {
                        if let player {
                            VideoPlayer(player: player)
                        } else {
                            Rectangle().fill(Color(uiColor: .secondarySystemBackground))
                                .overlay(ProgressView())
                        }
                    }
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    HStack(spacing: 14) {
                        Label(Self.duration(currentItem.durationSeconds), systemImage: "clock")
                        Label(ByteCountFormatter.string(fromByteCount: currentItem.byteCount, countStyle: .file), systemImage: "internaldrive")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    if !currentItem.labels.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("SCENE LABELS")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(1.3)
                            Text(currentItem.labels.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        library.toggleReviewQueue(currentItem)
                    } label: {
                        Label(
                            library.isInReviewQueue(currentItem) ? "Remove from review queue" : "Add to review queue",
                            systemImage: library.isInReviewQueue(currentItem) ? "checkmark.circle.fill" : "tray.and.arrow.down"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)

                    VStack(alignment: .leading, spacing: 11) {
                        Text("SAMPLED MOMENTS")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.3)
                        Text("Vision checked a few frames for visible text and visual labels. These moments are search aids; review the original video before using a clip.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(currentItem.frames) { frame in
                                    SampledFrameCard(frame: frame, url: library.frameURL(for: frame)) {
                                        selectedFrame = frame
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))

                    HStack(spacing: 12) {
                        ShareLink(item: library.videoURL(for: currentItem)) {
                            Label("Share video", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.cyan)

                        Button(role: .destructive) { confirmRemoval = true } label: {
                            Label("Remove copy", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("This is a private copy inside Screenshot Scout. Removing it here never deletes the original from Photos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
            }
            .navigationTitle("Video details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { player = AVPlayer(url: library.videoURL(for: item)) }
            .onDisappear { player?.pause() }
            .confirmationDialog("Remove this private copy?", isPresented: $confirmRemoval, titleVisibility: .visible) {
                Button("Remove from Screenshot Scout", role: .destructive) {
                    player?.pause()
                    library.remove(currentItem)
                    dismiss()
                }
            } message: {
                Text("The original video stays in Photos. This removes only the local copy and sampled frame index.")
            }
            .sheet(item: $selectedFrame) { frame in
                VideoFrameDescriptionEditor(
                    videoID: currentItem.id,
                    frame: frame,
                    imageURL: library.frameURL(for: frame)
                )
                .environmentObject(library)
                .presentationDragIndicator(.visible)
            }
        }
    }

    private static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct VideoCard: View {
    let item: IndexedVideo
    let thumbnailURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let thumbnailURL, let image = UIImage(contentsOfFile: thumbnailURL.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.white.opacity(0.06))
                        .overlay(Image(systemName: "video").foregroundStyle(.white.opacity(0.3)))
                }
            }
            .frame(height: 142)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                Text(Self.duration(item.durationSeconds))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.75), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(9)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(item.labels.prefix(2).joined(separator: " · ").capitalized.isEmpty ? "Video" : item.labels.prefix(2).joined(separator: " · ").capitalized)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(item.recognizedText.isEmpty ? "No visible text in sampled moments" : item.recognizedText.replacingOccurrences(of: "\n", with: " "))
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

    private static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds) : String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

private struct SampledFrameCard: View {
    let frame: IndexedVideoFrame
    let url: URL
    let onDescribe: () -> Void

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
            .frame(width: 156, height: 108)
            .clipped()
            Text("\(frame.timeSeconds, format: .number.precision(.fractionLength(1))) sec")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            if !frame.recognizedText.isEmpty {
                Text(frame.recognizedText.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 10, design: .rounded))
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
            }
            if let description = frame.sceneDescription, !description.isEmpty {
                Text(description)
                    .font(.system(size: 10, design: .rounded))
                    .lineLimit(4)
                    .foregroundStyle(.secondary)
            }
            Button(frame.sceneDescription == nil ? "Describe frame" : "Edit description", systemImage: "sparkles", action: onDescribe)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .buttonStyle(.bordered)
                .tint(.cyan)
        }
        .frame(width: 156, alignment: .leading)
    }
}

private struct VideoFrameDescriptionEditor: View {
    @EnvironmentObject private var library: ScreenshotLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var isGenerating = false
    @State private var errorMessage: String?

    let videoID: UUID
    let frame: IndexedVideoFrame
    let imageURL: URL

    init(videoID: UUID, frame: IndexedVideoFrame, imageURL: URL) {
        self.videoID = videoID
        self.frame = frame
        self.imageURL = imageURL
        _draft = State(initialValue: frame.sceneDescription ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let image = UIImage(contentsOfFile: imageURL.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Text("Frame at \(frame.timeSeconds, format: .number.precision(.fractionLength(1))) seconds")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("This describes one sampled frame. It does not analyze the video as a whole.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await generateDraft() }
                    } label: {
                        Label(isGenerating ? "Drafting on device…" : "Draft description", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(isGenerating || !FoundationModelsImageDescriber.isAvailable)

                    if !FoundationModelsImageDescriber.isAvailable {
                        Text("Description drafting needs iOS 27 and an available on-device model with image support. You can still write a description below.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    TextEditor(text: $draft)
                        .frame(minHeight: 130)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Frame description draft")

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button("Save description") {
                        saveDraft()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(18)
            }
            .navigationTitle("Frame description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func generateDraft() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            draft = try await FoundationModelsImageDescriber.describe(imageURL: imageURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveDraft() {
        do {
            try library.updateSceneDescription(for: videoID, frameIndex: frame.index, description: draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
