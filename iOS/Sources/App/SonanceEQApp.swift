import AVFAudio
import SwiftUI
import UniformTypeIdentifiers

@main
struct SonanceEQApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = EqualizerSession()

    var body: some Scene {
        WindowGroup { EqualizerView(session: session) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { session.checkpointForBackground() }
            }
    }
}

private struct EqualizerView: View {
    let session: EqualizerSession
    @State private var pickingFile = false
    @State private var showingPresets = false
    @State private var showingCorrection = false
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
                                      read: player.readAnalysis)
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
                            comparison: EqualizerComparison(hasReference: session.reference != nil,
                                                            listeningToReference: session.playingReference,
                                                            capture: session.captureReference, audition: session.auditionReference)
                        )
                        if let message = session.storageMessage {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }
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
        .sheet(isPresented: $showingCorrection) {
            OutputCorrectionView(session: session)
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
