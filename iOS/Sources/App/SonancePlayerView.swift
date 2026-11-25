import AVFAudio
import SwiftUI
import UniformTypeIdentifiers

private struct EqualizerView: View {
    let session: EqualizerSession
    @State private var pickingFile = false
    @State private var showingPresets = false
    @State private var showingHeadphoneCatalog = false
    @State private var showingCorrection = false
    @State private var showingListeningModes = false
    @State private var showingGuide = false
    @State private var workspace = AudioWorkspace.equalizer
    @State private var floatingCurve = FloatingCurve()

    private var player: PreviewPlayer { session.player }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AudioWorkspacePicker(workspace: $workspace)
                    if workspace == .live {
                        LiveAudioView(active: player.state == .playing, waitingMessage: "Play an audio file to see its output.",
                                      read: player.readAnalysis, readMetrics: player.readRenderMetrics)
                    } else {
                        EqualizerEditor(
                            settings: Binding(
                                get: {
                                    if session.playingReference, let reference = session.reference { return reference }
                                    return session.snapshot.settings
                                },
                                set: { updated in session.updateEQ { $0 = updated } }
                            ),
                            selectedBand: Binding(get: { session.snapshot.selectedBand }, set: session.selectBand),
                            sampleRate: player.sampleRate,
                            onEditingChanged: session.editingChanged,
                            onPresetLibrary: { showingPresets = true },
                            onHeadphoneCatalog: { showingHeadphoneCatalog = true },
                            comparison: EqualizerComparison(hasReference: session.reference != nil,
                                                            listeningToReference: session.playingReference,
                                                            capture: session.captureReference, audition: session.auditionReference)
                        )
                        if let message = session.storageMessage {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }
                        Button {
                            showingListeningModes = true
                        } label: {
                            Label("Listening & Sound Profiles", systemImage: "waveform.and.mic")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16))
                        pluginHelp
                    }
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 4) {
                FloatingPlayer(player: player, curve: floatingCurve) { pickingFile = true }
                    .frame(maxWidth: 600)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Sonance EQ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Getting Started", systemImage: "questionmark.circle") { showingGuide = true }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("gettingStarted")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Output Correction", systemImage: "headphones") { showingCorrection = true }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("outputCorrection")
                }
            }
        }
        .tint(EqualizerEditor.accent)
        .sheet(isPresented: $showingPresets) {
            PresetLibraryView(library: session.presets, session: session)
                .tint(EqualizerEditor.accent)
        }
        .sheet(isPresented: $showingHeadphoneCatalog) {
            AutoEqCatalogView(session: session)
                .tint(EqualizerEditor.accent)
        }
        .sheet(isPresented: $showingCorrection) {
            OutputCorrectionView(session: session)
                .tint(EqualizerEditor.accent)
        }
        .sheet(isPresented: $showingListeningModes) {
            SpeechListeningView(session: session)
                .tint(EqualizerEditor.accent)
        }
        .sheet(isPresented: $showingGuide) {
            ListeningGuideView()
                .tint(EqualizerEditor.accent)
        }
        .onChange(of: workspace) { _, current in floatingCurve.showSignal(current == .live) }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): player.select(url)
            case .failure: player.error = "The audio file couldn’t be opened."
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            Task { @MainActor in player.handleInterruption(notification) }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            Task { @MainActor in player.handleRouteChange(notification) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange)) { notification in
            Task { @MainActor in player.handleConfigurationChange(notification) }
        }
        .modifier(AudioSessionLifecycleObserver(player: player))
    }

    private var pluginHelp: some View {
        DisclosureGroup("Use Sonance EQ in another app") {
            Text("Add Sonance EQ as an effect in a compatible AUv3 host. The host controls playback and saves the plug-in’s settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct AudioSessionLifecycleObserver: ViewModifier {
    let player: PreviewPlayer

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.didBecomeInactiveNotification)) { notification in
                    Task { @MainActor in player.handleSystemDeactivation(notification) }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.resumptionRecommendationNotification)) { notification in
                    Task { @MainActor in player.handleResumptionRecommendation(notification) }
                }
        } else {
            content
        }
    }
}

private struct ListeningGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Play a file") {
                    Label("Tap Open Audio and choose a mono or stereo file from Files.", systemImage: "1.circle")
                    Label("Tap Play, then choose a preset or adjust the EQ curve.", systemImage: "2.circle")
                    Label("Use Bypass EQ to compare the original and adjusted sound.", systemImage: "3.circle")
                }
                Section("Listen to speech") {
                    Text("Choose Listening & Sound Profiles for everyday tone presets, speech starting curves, or a preference-guided headphone sound. You can edit and save any suggestion.")
                }
                Section("Use another audio app") {
                    Text("Add Sonance EQ as an effect in a compatible AUv3 host. Choose a speech curve from the host's Sonance Presets menu. The host controls its own effect settings.")
                    Text("The Sonance player does not receive other apps' audio directly. A separate compatible host and route are needed, and compatibility varies.")
                        .foregroundStyle(.secondary)
                }
                Section("Keep your sound") {
                    Text("Use Presets → Preset Library to save or export a curve. Output Correction can apply a saved preset to a recognized output during Sonance file playback.")
                }
                Section("Use Siri or Shortcuts") {
                    Text("Say “Enable EQ bypass in Sonance EQ” to hear the selected file without EQ, or “Disable EQ bypass in Sonance EQ” to restore your saved curve.")
                    Text("These actions change the standalone Sonance player. They do not control audio in another app.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Getting Started")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}


public struct SonancePlayerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = EqualizerSession.shared

    public init() {
        SonanceAppShortcuts.updateAppShortcutParameters()
    }

    public var body: some View {
        EqualizerView(session: session)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { session.checkpointForBackground() }
            }
    }
}
