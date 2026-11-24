import AudioToolbox
import AVFAudio
import CoreAudioKit
import Observation
import SwiftUI

final class SonanceAudioUnitViewController: AUViewController, AUAudioUnitFactory {
    private let editor = HostedEqualizer()
    private var audioUnit: SonanceAudioUnit?

    nonisolated func createAudioUnit(with description: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try SonanceAudioUnit(componentDescription: description, options: [])
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.audioUnit = unit
            if self.isViewLoaded { self.editor.connect(to: unit) }
        }
        return unit
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 390, height: 640)
        let host = UIHostingController(rootView: HostedEditorView(editor: editor))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        if let audioUnit { editor.connect(to: audioUnit) }
    }
}

@MainActor @Observable
private final class HostedEqualizer {
    private(set) var settings = MobileEQSettings()
    private(set) var sampleRate = 48_000.0
    private(set) var isReady = false
    var selectedBand: Int? = 5

    @ObservationIgnored private var unit: SonanceAudioUnit?
    @ObservationIgnored private var tree: AUParameterTree?
    @ObservationIgnored private var token: AUParameterObserverToken?
    @ObservationIgnored private var formatObservation: NSKeyValueObservation?
    @ObservationIgnored private lazy var analysis = AudioAnalysisMonitor()

    func connect(to unit: SonanceAudioUnit) {
        guard self.unit !== unit, let tree = unit.parameterTree else { return }
        if let token { self.tree?.removeParameterObserver(token) }
        self.unit = unit
        self.tree = tree
        token = tree.token(byAddingParameterObserver: { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        })
        formatObservation = unit.outputBusses[0].observe(\.format) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
        isReady = true
    }

    func apply(_ updated: MobileEQSettings) {
        guard let tree else { return }
        updated.apply(to: tree, changedFrom: settings, originator: token)
        refresh()
    }

    func readAnalysis() -> AudioAnalysisFrame? {
        guard let unit else { return nil }
        return analysis.read(unit.analysisCapture)
    }

    func readRenderMetrics() -> AudioRenderMetrics? {
        guard let tree else { return nil }
        return AudioRenderMetrics(parameterTree: tree)
    }

    private func refresh() {
        guard let unit else { return }
        settings = unit.settings
        selectedBand = settings.selection(selectedBand)
        sampleRate = unit.outputBusses[0].format.sampleRate
    }

    deinit {
        if let token { tree?.removeParameterObserver(token) }
    }
}

private struct HostedEditorView: View {
    @Bindable var editor: HostedEqualizer
    @State private var workspace = AudioWorkspace.equalizer

    var body: some View {
        Group {
            if editor.isReady {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        AudioWorkspacePicker(workspace: $workspace)
                        if workspace == .live {
                            LiveAudioView(active: true, waitingMessage: "Start playback in the host to see its output.",
                                          read: editor.readAnalysis, readMetrics: editor.readRenderMetrics)
                        } else {
                            EqualizerEditor(settings: Binding(get: { editor.settings }, set: editor.apply),
                                            selectedBand: $editor.selectedBand, sampleRate: editor.sampleRate)
                        }
                    }
                    .frame(maxWidth: 600)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ProgressView("Loading equalizer…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .tint(EqualizerEditor.accent)
    }
}
