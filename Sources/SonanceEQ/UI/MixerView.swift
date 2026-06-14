import SwiftUI

/// Per-app mixer: independent volume, mute, and output-device routing for each app playing audio.
struct MixerView: View {
    @Bindable var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 480, height: 470)
        .onAppear { app.refreshApps(); app.refreshDevices() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("App Mixer").font(.headline)
                Text("Independent volume & output per app").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("On", isOn: Binding(get: { app.mixerEnabled }, set: { app.setMixerEnabled($0) }))
                .toggleStyle(.switch)
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    @ViewBuilder private var content: some View {
        if app.availableApps.isEmpty {
            ContentUnavailableView("No apps are playing audio", systemImage: "speaker.slash",
                                   description: Text("Start playback in an app, then tap Refresh."))
                .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(app.availableApps) { row($0) }
                }
                .padding(12)
            }
        }
    }

    private func row(_ audioApp: AudioApp) -> some View {
        let channel = app.mixer.channel(audioApp.bundleID, name: audioApp.name)
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(audioApp.name).frame(width: 120, alignment: .leading).lineLimit(1)
                Button { app.setAppMuted(!channel.muted, audioApp) } label: {
                    Image(systemName: channel.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(channel.muted ? .red : .primary)
                }
                .buttonStyle(.borderless).frame(width: 18)
                Slider(value: Binding(get: { channel.volume }, set: { app.setAppVolume($0, audioApp) }),
                       in: 0...MixerChannel.maxVolume)
                Text("\(Int(channel.volume * 100))%")
                    .font(.caption2.monospaced()).frame(width: 40, alignment: .trailing)
            }
            HStack(spacing: 8) {
                Text("Output").font(.caption2).foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)
                Menu(outputLabel(channel)) {
                    Button("Default Output") { app.setAppOutput(nil, audioApp) }
                    if !app.availableDevices.isEmpty { Divider() }
                    ForEach(app.availableDevices) { device in
                        Button(device.name) { app.setAppOutput(device.uid, audioApp) }
                    }
                }
                .frame(maxWidth: 220, alignment: .leading)
                Spacer()
                if !channel.isPassthrough {
                    Button("Reset") { app.resetAppChannel(audioApp) }.controlSize(.mini)
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func outputLabel(_ channel: MixerChannel) -> String {
        guard let uid = channel.outputDeviceUID else { return "Default Output" }
        return app.availableDevices.first { $0.uid == uid }?.name ?? "Custom device"
    }

    private var footer: some View {
        HStack {
            if !app.mixerEnabled {
                Label("Mixer is off — flip On to apply", systemImage: "info.circle")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Label("Best used with the system EQ off for these apps", systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") { app.refreshApps(); app.refreshDevices() }.controlSize(.small)
        }
        .padding(12)
    }
}
