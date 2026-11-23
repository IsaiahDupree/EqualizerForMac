import AVKit
import SwiftUI

struct VideoDetailView: View {
    @EnvironmentObject private var library: ScreenshotLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var confirmRemoval = false

    let item: IndexedVideo

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
                        Label(Self.duration(item.durationSeconds), systemImage: "clock")
                        Label(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file), systemImage: "internaldrive")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    if !item.labels.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("SCENE LABELS")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(1.3)
                            Text(item.labels.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        library.toggleReviewQueue(item)
                    } label: {
                        Label(
                            library.isInReviewQueue(item) ? "Remove from review queue" : "Add to review queue",
                            systemImage: library.isInReviewQueue(item) ? "checkmark.circle.fill" : "tray.and.arrow.down"
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
                                ForEach(item.frames) { frame in
                                    SampledFrameCard(frame: frame, url: library.frameURL(for: frame))
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))

                    HStack(spacing: 12) {
                        ShareLink(item: library.videoURL(for: item)) {
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
                    library.remove(item)
                    dismiss()
                }
            } message: {
                Text("The original video stays in Photos. This removes only the local copy and sampled frame index.")
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
        }
        .frame(width: 156, alignment: .leading)
    }
}
