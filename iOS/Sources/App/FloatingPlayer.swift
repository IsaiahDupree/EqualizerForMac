import SwiftUI

struct FloatingPlayer: View {
    let player: PreviewPlayer
    let curve: FloatingCurve
    let openAudio: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                fileButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                if curve.isSupported, player.state == .playing || player.state == .paused || curve.isActive {
                    Button(action: curve.toggle) {
                        Image(systemName: curve.isActive ? "pip.exit" : "pip.enter")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(EqualizerEditor.accent)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!curve.isPossible && !curve.isActive)
                    .accessibilityLabel(curve.isActive ? "Close Picture in Picture" : "Open Picture in Picture")
                    .accessibilityIdentifier("floatingCurve")
                }
                if player.state == .playing || player.state == .paused {
                    sleepTimer
                    Button(action: player.stop) {
                        Image(systemName: "stop.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(.primary.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop")
                    .accessibilityIdentifier("stopAudio")
                }
                transport
            }
            if let error = player.error ?? curve.message {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.primary.opacity(0.09))
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
    }

    private var fileButton: some View {
        Button(action: openAudio) {
            HStack(spacing: 9) {
                fileArtwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fileName ?? "Open Audio")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .truncationMode(.middle)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Audio")
        .accessibilityValue(player.fileName.map { "\($0), \(status)" } ?? status)
        .accessibilityIdentifier("openAudio")
    }

    @ViewBuilder private var fileArtwork: some View {
        if curve.isSupported, player.state == .playing || player.state == .paused || curve.isActive {
            FloatingCurvePreview(player: player, curve: curve)
                .frame(width: 54, height: 42)
                .background(Color(red: 0.05, green: 0.07, blue: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "folder")
                .font(.body.weight(.semibold))
                .foregroundStyle(EqualizerEditor.accent)
                .frame(width: 44, height: 44)
                .background(EqualizerEditor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
        }
    }

    private var status: String {
        switch player.state {
        case .idle: return player.fileName == nil ? "Files" : "Ready to play"
        case .starting: return "Starting…"
        case .playing: return player.outputName.map { "Playing on \($0)" } ?? "Playing"
        case .paused: return "Paused"
        }
    }

    private var transport: some View {
        let symbol: String
        let title: String
        switch player.state {
        case .idle, .paused: (symbol, title) = ("play.fill", "Play")
        case .starting: (symbol, title) = ("xmark", "Cancel")
        case .playing: (symbol, title) = ("pause.fill", "Pause")
        }
        return Button {
            switch player.state {
            case .idle, .paused: Task { await player.play() }
            case .starting: player.stop()
            case .playing: player.pause()
            }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(player.fileName == nil ? Color.secondary : .white)
                .frame(width: 44, height: 44)
                .background(player.fileName == nil ? .primary.opacity(0.07) : Color(red: 0.14, green: 0.34, blue: 0.78),
                            in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(player.fileName == nil)
        .accessibilityLabel(title)
        .accessibilityIdentifier("playAudio")
    }

    private var sleepTimer: some View {
        Menu {
            ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                Button("Stop in \(minutes) minutes") {
                    player.setSleepTimer(minutes: minutes)
                }
            }
            if player.sleepTimerMinutes != nil {
                Button("Cancel sleep timer", role: .destructive) {
                    player.setSleepTimer(minutes: nil)
                }
            }
        } label: {
            Image(systemName: player.sleepTimerMinutes == nil ? "moon.zzz" : "moon.zzz.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(EqualizerEditor.accent)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(player.sleepTimerMinutes.map { "Sleep timer, stops in \($0) minutes" } ?? "Set sleep timer")
        .accessibilityIdentifier("sleepTimer")
    }
}
