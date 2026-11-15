import AVFoundation
import SwiftUI

struct ListeningPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVAudioPlayer?
    @State private var sample: ListeningSample.Comparison?
    @State private var playbackError = false
    @State private var playingTuned: Bool?
    @State private var playbackEnd: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preview EQ").font(.title2.bold())
            Text("Hear the same sample at matched levels. The preview plays locally without capturing system audio.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { play(tuned: false) } label: {
                    Label("Original", systemImage: playingTuned == false ? "speaker.wave.2.fill" : "play.fill")
                }
                Button { play(tuned: true) } label: {
                    Label("Vocal", systemImage: playingTuned == true ? "speaker.wave.2.fill" : "play.fill")
                }
                Button("Stop") { stop() }.disabled(player == nil)
            }
            if playbackError {
                Text("Couldn’t play the preview. Check your output and try again.")
                    .foregroundStyle(.red)
            }
            Divider()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .frame(width: 420)
        .onDisappear(perform: stop)
    }

    private func play(tuned: Bool) {
        stop()
        let comparison = sample ?? ListeningSample.render()
        sample = comparison
        let audio = ListeningSample.wave(tuned ? comparison.tuned : comparison.original)
        do {
            let next = try AVAudioPlayer(data: audio)
            guard next.play() else { playbackError = true; return }
            playbackError = false
            player = next
            playingTuned = tuned
            playbackEnd = Task { @MainActor in
                try? await Task.sleep(for: .seconds(next.duration))
                guard !Task.isCancelled else { return }
                player = nil
                playingTuned = nil
                playbackEnd = nil
            }
        } catch {
            playbackError = true
        }
    }

    private func stop() {
        playbackEnd?.cancel()
        playbackEnd = nil
        player?.stop()
        player = nil
        playingTuned = nil
    }
}
