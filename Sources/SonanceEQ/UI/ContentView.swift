import SwiftUI

struct ContentView: View {
    @Bindable var app: AppState
    @State private var showingBrowser = false
    @State private var showingPaywall = false
    @State private var showingMixer = false
    @State private var showingRecorder = false
    @State private var showingAnalytics = false

    /// Present the paywall and record the impression (top of the conversion funnel).
    private func presentPaywall() {
        app.license.paywallShown()
        showingPaywall = true
    }

    /// Run `action` if the feature is unlocked, otherwise present the paywall.
    private func requirePro(_ feature: ProFeature, _ action: () -> Void) {
        if app.license.shouldShowPaywall(for: feature) { presentPaywall() } else { action() }
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
                ErrorBanner(message: message)
            }
            Divider()
            footer
        }
        .padding(22)
        .frame(width: 560)
        .sheet(isPresented: $showingBrowser) { PresetBrowserView(app: app) }
        .sheet(isPresented: $showingPaywall) { ProPaywallSheet(app: app) }
        .sheet(isPresented: $showingMixer) { MixerView(app: app) }
        .sheet(isPresented: $showingRecorder) { RecorderView(app: app) }
        .sheet(isPresented: $app.showingAbout) { AboutView() }
        .sheet(isPresented: $showingAnalytics) { PurchaseAnalyticsView(app: app) }
        .onAppear(perform: openLaunchArgPanel)
    }

    /// Auto-present a panel from a launch argument (`--screen mixer|recorder`) for demos/screenshots.
    /// Routed through the same `requirePro` gate as the Mixer/Record buttons so this can't be used
    /// to open Pro-only panels without an entitlement (shows the paywall instead, same as a tap would).
    private func openLaunchArgPanel() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--screen"), i + 1 < args.count else { return }
        switch args[i + 1] {
        case "mixer": requirePro(.perAppEQ) { showingMixer = true }
        case "recorder": requirePro(.audioRecorder) { showingRecorder = true }
        default: break
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("app.title", bundle: .main).font(.title2.bold())
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(app.isRunning ? .green : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            if app.license.isPro {
                Text("header.pro", bundle: .main).font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.tint.opacity(0.2), in: Capsule())
            } else {
                Button { presentPaywall() } label: {
                    Label {
                        Text("header.unlock", bundle: .main)
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                }
                .controlSize(.small)
            }
            Toggle(isOn: Binding(
                get: { app.bypassed },
                set: { app.bypassed = $0; app.pushSettings() }
            )) {
                Text("header.bypass", bundle: .main)
            }
            .toggleStyle(.switch)
            .disabled(!app.isRunning)
            .help("header.bypass.help")
            Button { app.toggle() } label: {
                Text(app.isRunning ? "header.stop" : "header.start", bundle: .main)
            }
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
            Text("permission.banner.title", bundle: .main)
                .font(.caption)
            Spacer()
            Button { app.openPrivacySettings() } label: {
                Text("permission.banner.button", bundle: .main)
            }
        }
        .padding(10)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Per-app target

    private var targetRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "app.badge").foregroundStyle(.secondary)
            Text("target.label", bundle: .main).font(.caption).foregroundStyle(.secondary)
            if app.license.canUse(.perAppEQ) {
                Menu {
                    Button { app.setAllApps() } label: {
                        Label {
                            Text("target.allApps", bundle: .main)
                        } icon: {
                            Image(systemName: app.eqTarget.isAllApps ? "checkmark" : "")
                        }
                    }
                    if !app.availableApps.isEmpty { Divider() }
                    ForEach(app.availableApps) { audioApp in
                        Button { app.toggleApp(audioApp.bundleID) } label: {
                            Label {
                                HStack(spacing: 4) {
                                    AudioAppIconView(audioApp: audioApp, size: 14)
                                    Text(audioApp.name)
                                }
                            } icon: {
                                if app.isAppSelected(audioApp.bundleID) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    Divider()
                    Button { app.refreshApps() } label: {
                        Text("target.refresh", bundle: .main)
                    }
                } label: {
                    Text(app.targetLabel)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .onAppear { app.refreshApps() }
            } else {
                Button { presentPaywall() } label: {
                    Label {
                        Text("target.perAppEQ.locked", bundle: .main)
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                }
                .controlSize(.small)
            }
            Spacer()
            Button {
                requirePro(.perAppEQ) { showingMixer = true }
            } label: {
                Label {
                    Text("button.mixer", bundle: .main)
                } icon: {
                    Image(systemName: app.license.canUse(.perAppEQ) ? "slider.vertical.3" : "lock.fill")
                }
            }
            .controlSize(.small)
            .help("target.mixer.help")
            Button {
                requirePro(.audioRecorder) { showingRecorder = true }
            } label: {
                Label {
                    Text("button.record", bundle: .main)
                } icon: {
                    Image(systemName: app.license.canUse(.audioRecorder) ? "record.circle" : "lock.fill")
                }
            }
            .controlSize(.small)
            .help("target.recorder.help")
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
                Label {
                    Text("button.headphones", bundle: .main)
                } icon: {
                    Image(systemName: app.license.canUse(.autoEqLibrary) ? "headphones" : "lock.fill")
                }
            }
            .controlSize(.small)
        }
    }

    // MARK: Preamp

    private var preampRow: some View {
        HStack(spacing: 12) {
            Text("control.preamp", bundle: .main).font(.caption).frame(width: 56, alignment: .leading)
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
                    Text("control.midSide", bundle: .main).tag(AppState.ChannelTarget.mid)
                    Text("control.stereo", bundle: .main).tag(AppState.ChannelTarget.side)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
                Text("editing the \(app.editTarget == .side ? "Side (stereo width)" : "Mid (center)") channel")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(isOn: Binding(get: { app.midSideEnabled },
                                 set: { if app.license.canUse(.parametricEQ) { app.setMidSide($0) } else { presentPaywall() } })) {
                proLabel("control.midSide", feature: .parametricEQ)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("control.midSide.help")
        }
    }

    /// A control label that shows a lock when its feature is gated.
    private func proLabel(_ titleKey: LocalizedStringKey, feature: ProFeature) -> some View {
        HStack(spacing: 4) {
            Text(titleKey)
            if !app.license.canUse(feature) {
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Phase mode

    private var phaseRow: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { app.linearPhase },
                                 set: { if app.license.canUse(.parametricEQ) { app.linearPhase = $0; app.pushSettings() } else { presentPaywall() } })) {
                proLabel("control.linearPhase", feature: .parametricEQ)
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
            Button { showingAnalytics = true } label: { Image(systemName: "chart.bar.xaxis") }
                .buttonStyle(.borderless)
                .help("Purchase & diagnostics log — useful when reporting a problem")
            Button { app.showingAbout = true } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
                .help("About Sonance EQ")
        }
    }
}
