import SwiftUI

struct ContentView: View {
    @Bindable var app: AppState

    var body: some View {
        VStack(spacing: 18) {
            header
            if app.permission.status == .denied { permissionBanner }
            presetRow
            bandsRow
            preampRow
            if let message = app.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(22)
        .frame(width: 560)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sonance EQ").font(.title2.bold())
                Text(app.isRunning ? "Active · \(app.outputDeviceName)" : "Stopped")
                    .font(.caption)
                    .foregroundStyle(app.isRunning ? .green : .secondary)
            }
            Spacer()
            Toggle("Bypass", isOn: Binding(
                get: { app.bypassed },
                set: { app.bypassed = $0; app.pushSettings() }
            ))
            .toggleStyle(.switch)
            .disabled(!app.isRunning)
            Button(app.isRunning ? "Stop" : "Start EQ") { app.toggle() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("Audio Capture permission is required to equalize system audio.")
                .font(.caption)
            Spacer()
            Button("Open Settings") { app.openPrivacySettings() }
        }
        .padding(10)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Presets

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(Presets.all) { preset in
                Button(preset.name) { app.apply(preset.bands) }
                    .controlSize(.small)
            }
            Spacer()
        }
    }

    // MARK: Bands (10-band graphic faders)

    private var bandsRow: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(app.bands.indices, id: \.self) { index in
                bandFader(index)
            }
        }
        .padding(.vertical, 4)
    }

    private func bandFader(_ index: Int) -> some View {
        VStack(spacing: 6) {
            Text(app.bands[index].gainLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { app.bands[index].gain },
                    set: { app.setGain($0, at: index) }
                ),
                in: -12...12
            )
            .controlSize(.mini)
            .frame(width: 150)
            .rotationEffect(.degrees(-90))
            .frame(width: 28, height: 150)
            Text(app.bands[index].freqLabel)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Preamp

    private var preampRow: some View {
        HStack(spacing: 12) {
            Text("Preamp").font(.caption).frame(width: 56, alignment: .leading)
            Slider(
                value: Binding(get: { app.preampDb }, set: { app.preampDb = $0; app.pushSettings() }),
                in: -12...12
            )
            Text(String(format: "%+.1f dB", app.preampDb))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 64, alignment: .trailing)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Reset") { app.resetFlat() }
                .controlSize(.small)
            Spacer()
            Text("System-wide · driverless")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
