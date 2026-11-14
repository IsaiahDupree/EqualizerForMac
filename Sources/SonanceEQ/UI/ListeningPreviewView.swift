import AVFoundation
import SwiftUI

struct ListeningPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVAudioPlayer?
    @State private var sample: ListeningSample.Comparison?
    @State private var playbackError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preview EQ").font(.title2.bold())
            Text("Hear the same sample at matched levels. The preview plays locally without capturing system audio.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { play(tuned: false) } label: {
                    Label("Original", systemImage: "play.fill")
                }
                Button { play(tuned: true) } label: {
                    Label("Vocal", systemImage: "play.fill")
                }
                Button("Stop") { stop() }
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
            playbackError = !next.play()
            if !playbackError { player = next }
        } catch {
            playbackError = true
        }
    }

    private func stop() {
        player?.stop()
        player = nil
    }
}
