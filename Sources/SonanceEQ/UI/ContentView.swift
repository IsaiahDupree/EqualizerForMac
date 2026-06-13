import SwiftUI

struct ContentView: View {
    @Bindable var app: AppState
    @State private var showingBrowser = false

    var body: some View {
        VStack(spacing: 18) {
            header
            if app.permission.status == .denied { permissionBanner }
            presetRow
            ResponseCurveView(app: app)
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
        .sheet(isPresented: $showingBrowser) { PresetBrowserView(app: app) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sonance EQ").font(.title2.bold())
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(app.isRunning ? .green : .secondary)
                    .lineLimit(1)
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

    private var headerSubtitle: String {
        if app.isRunning {
            if let preset = app.activePresetName { return "Active · \(preset)" }
            return "Active · \(app.outputDeviceName)"
        }
        return app.activePresetName ?? "Stopped"
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
            Button {
                showingBrowser = true
            } label: {
                Label("Headphones", systemImage: "headphones")
            }
            .controlSize(.small)
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
            Button("Import…") { app.importPreset() }
                .controlSize(.small)
            Button("Export…") { app.exportCurrentPreset() }
                .controlSize(.small)
            Spacer()
            Text("System-wide · driverless")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
