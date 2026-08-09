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
        if app.isRefreshingApps || app.isRefreshingDevices {
            VStack(spacing: 12) {
                ProgressView()
                Text("Refreshing…").foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)
            .accessibilityLabel("Loading audio apps")
        } else if app.availableApps.isEmpty {
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
                    .accessibilityLabel(audioApp.name)
                Button { app.setAppMuted(!channel.muted, audioApp) } label: {
                    Image(systemName: channel.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(channel.muted ? .red : .primary)
                }
                .buttonStyle(.borderless).frame(width: 18)
                .accessibilityLabel("\(audioApp.name) \(channel.muted ? "muted" : "unmuted")")
                .accessibilityHint("Toggle mute")
                Slider(value: Binding(get: { channel.volume }, set: { app.setAppVolume($0, audioApp) }),
                       in: 0...MixerChannel.maxVolume)
                .accessibilityLabel("\(audioApp.name) volume")
                .accessibilityValue("\(Int(channel.volume * 100))%")
                Text("\(Int(channel.volume * 100))%")
                    .font(.caption2.monospaced()).frame(width: 40, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 8) {
                Text("Output").font(.caption2).foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)
                    .accessibilityHidden(true)
                Menu(outputLabel(channel)) {
                    Button("Default Output") { app.setAppOutput(nil, audioApp) }
                    if !app.availableDevices.isEmpty { Divider() }
                    ForEach(app.availableDevices) { device in
                        Button(device.name) { app.setAppOutput(device.uid, audioApp) }
                    }
                }
                .frame(maxWidth: 220, alignment: .leading)
                .accessibilityLabel("\(audioApp.name) output device")
                .accessibilityValue(outputLabel(channel))
                Spacer()
                if !channel.isPassthrough {
                    Button("Reset") { app.resetAppChannel(audioApp) }
                        .controlSize(.mini)
                        .accessibilityLabel("Reset \(audioApp.name) to defaults")
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
                    .accessibilityLabel("Mixer is disabled")
            } else {
                Label("Best used with the system EQ off for these apps", systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityLabel("Tip: disable system EQ for best results")
            }
            Spacer()
            Button {
                app.refreshApps()
                app.refreshDevices()
            } label: {
                if app.isRefreshingApps || app.isRefreshingDevices {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.8, anchor: .center)
                        Text("Refreshing")
                    }
                } else {
                    Text("Refresh")
                }
            }
            .controlSize(.small)
            .accessibilityLabel("Refresh audio apps and devices")
        }
        .padding(12)
    }
}
