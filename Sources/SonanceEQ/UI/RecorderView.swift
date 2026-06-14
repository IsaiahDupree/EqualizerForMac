import SwiftUI

/// Audio recorder panel: capture system audio (or chosen apps) to a WAV / ALAC / AAC file. The capture
/// is an unmuted observer tap, so playback is untouched while recording.
struct RecorderView: View {
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
        .frame(width: 420, height: 320)
        .onAppear { app.refreshApps() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Audio Recorder").font(.headline)
                Text("Capture what's playing to a file").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 16) {
            // Big record button + elapsed time.
            VStack(spacing: 8) {
                Button {
                    app.toggleRecording()
                } label: {
                    Image(systemName: app.isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.system(size: 56))
                        .foregroundStyle(app.isRecording ? .red : .red.opacity(0.85))
                        .symbolEffect(.pulse, isActive: app.isRecording)
                }
                .buttonStyle(.plain)
                .help(app.isRecording ? "Stop recording" : "Choose a file and start recording")

                Text(timeString(app.recordingElapsed))
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .foregroundStyle(app.isRecording ? .primary : .secondary)
            }

            // Source + format (locked while recording).
            HStack(spacing: 12) {
                Label("Source", systemImage: "speaker.wave.2").font(.caption).frame(width: 70, alignment: .leading)
                Menu(app.recordTargetLabel) {
                    Button { app.setRecordAllApps() } label: {
                        Label("All Apps", systemImage: app.recordTarget.isAllApps ? "checkmark" : "")
                    }
                    if !app.availableApps.isEmpty { Divider() }
                    ForEach(app.availableApps) { audioApp in
                        Button { app.toggleRecordApp(audioApp.bundleID) } label: {
                            Label(audioApp.name, systemImage: app.isRecordAppSelected(audioApp.bundleID) ? "checkmark" : "")
                        }
                    }
                    Divider()
                    Button("Refresh list") { app.refreshApps() }
                }
                .fixedSize()
            }
            .disabled(app.isRecording)

            HStack(spacing: 12) {
                Label("Format", systemImage: "waveform").font(.caption).frame(width: 70, alignment: .leading)
                Picker("", selection: Binding(get: { app.recordingFormat },
                                              set: { app.recordingFormat = $0 })) {
                    ForEach(RecordingFormat.allCases) { fmt in
                        Text(fmt.label).tag(fmt)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .disabled(app.isRecording)
        }
        .padding(16)
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if app.isRecording {
                Label("Recording — playback is unaffected", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption2).foregroundStyle(.red)
            } else if app.lastRecordingURL != nil {
                Button {
                    app.revealLastRecording()
                } label: {
                    Label("Reveal last recording", systemImage: "folder")
                }
                .controlSize(.small)
            } else {
                Text("Saved where you choose · stays on your Mac")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }

    private func timeString(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
