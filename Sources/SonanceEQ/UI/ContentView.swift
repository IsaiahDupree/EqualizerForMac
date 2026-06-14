import SwiftUI

struct ContentView: View {
    @Bindable var app: AppState
    @State private var showingBrowser = false
    @State private var showingPaywall = false
    @State private var showingMixer = false

    /// Run `action` if the feature is unlocked, otherwise present the paywall.
    private func requirePro(_ feature: ProFeature, _ action: () -> Void) {
        if app.license.canUse(feature) { action() } else { showingPaywall = true }
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            if app.permission.status == .denied { permissionBanner }
            targetRow
            presetRow
            stereoRow
            ResponseCurveView(app: app)
            preampRow
            phaseRow
            if let message = app.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .padding(22)
        .frame(width: 560)
        .sheet(isPresented: $showingBrowser) { PresetBrowserView(app: app) }
        .sheet(isPresented: $showingPaywall) { PaywallView(app: app) }
        .sheet(isPresented: $showingMixer) { MixerView(app: app) }
        .sheet(isPresented: $app.showingAbout) { AboutView() }
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
            if app.license.isPro {
                Text("PRO").font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.tint.opacity(0.2), in: Capsule())
            } else {
                Button { showingPaywall = true } label: {
                    Label("Unlock Pro", systemImage: "lock.fill")
                }
                .controlSize(.small)
            }
            Toggle("Bypass", isOn: Binding(
                get: { app.bypassed },
                set: { app.bypassed = $0; app.pushSettings() }
            ))
            .toggleStyle(.switch)
            .disabled(!app.isRunning)
            .help("Pass audio through unprocessed for an A/B comparison")
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

    // MARK: Per-app target

    private var targetRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "app.badge").foregroundStyle(.secondary)
            Text("Equalize").font(.caption).foregroundStyle(.secondary)
            if app.license.canUse(.perAppEQ) {
                Menu {
                    Button { app.setAllApps() } label: {
                        Label("All Apps", systemImage: app.eqTarget.isAllApps ? "checkmark" : "")
                    }
                    if !app.availableApps.isEmpty { Divider() }
                    ForEach(app.availableApps) { audioApp in
                        Button { app.toggleApp(audioApp.bundleID) } label: {
                            Label(audioApp.name, systemImage: app.isAppSelected(audioApp.bundleID) ? "checkmark" : "")
                        }
                    }
                    Divider()
                    Button("Refresh list") { app.refreshApps() }
                } label: {
                    Text(app.targetLabel)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .onAppear { app.refreshApps() }
            } else {
                Button { showingPaywall = true } label: {
                    Label("All Apps · per-app EQ is Pro", systemImage: "lock.fill")
                }
                .controlSize(.small)
            }
            Spacer()
            Button {
                requirePro(.perAppEQ) { showingMixer = true }
            } label: {
                Label("Mixer", systemImage: app.license.canUse(.perAppEQ) ? "slider.vertical.3" : "lock.fill")
            }
            .controlSize(.small)
            .help("Independent volume and output device per app")
        }
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
                requirePro(.autoEqLibrary) { showingBrowser = true }
            } label: {
                Label("Headphones", systemImage: app.license.canUse(.autoEqLibrary) ? "headphones" : "lock.fill")
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

    // MARK: Stereo / Mid-Side

    private var stereoRow: some View {
        HStack(spacing: 8) {
            if app.midSideEnabled {
                Picker("", selection: Binding(get: { app.editTarget },
                                              set: { app.editTarget = $0 })) {
                    Text("Mid").tag(AppState.ChannelTarget.mid)
                    Text("Side").tag(AppState.ChannelTarget.side)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
                Text("editing the \(app.editTarget == .side ? "Side (stereo width)" : "Mid (center)") channel")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(isOn: Binding(get: { app.midSideEnabled },
                                 set: { if app.license.canUse(.parametricEQ) { app.setMidSide($0) } else { showingPaywall = true } })) {
                proLabel("Mid-Side", feature: .parametricEQ)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("EQ the mono center and the stereo width with separate curves")
        }
    }

    /// A control label that shows a lock when its feature is gated.
    private func proLabel(_ title: String, feature: ProFeature) -> some View {
        HStack(spacing: 4) {
            Text(title)
            if !app.license.canUse(feature) {
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Phase mode

    private var phaseRow: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { app.linearPhase },
                                 set: { if app.license.canUse(.parametricEQ) { app.linearPhase = $0; app.pushSettings() } else { showingPaywall = true } })) {
                proLabel("Linear Phase", feature: .parametricEQ)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("Same EQ curve with zero phase distortion · adds a little latency")

            if app.linearPhase {
                Text(String(format: "+%.0f ms latency", app.latencyMs))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("System-wide · driverless")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Reset") { app.resetFlat() }
                .controlSize(.small)
            Button("Import…") { requirePro(.importExport) { app.importPreset() } }
                .controlSize(.small)
            Button("Export…") { requirePro(.importExport) { app.exportCurrentPreset() } }
                .controlSize(.small)
            Spacer()
            Button { app.showingAbout = true } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
                .help("About Sonance EQ")
        }
    }
}
