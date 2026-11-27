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
    @State private var showingHeadphoneCatalog = false

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
                                            selectedBand: $editor.selectedBand, sampleRate: editor.sampleRate,
                                            onHeadphoneCatalog: { showingHeadphoneCatalog = true })
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
        .sheet(isPresented: $showingHeadphoneCatalog) {
            HostedHeadphoneCorrectionCatalog { settings in editor.apply(settings) }
                .tint(EqualizerEditor.accent)
        }
    }
}

/// The AUv3 host has no PreviewPlayer/EqualizerSession, so it applies catalog
/// settings directly to its connected AU parameter tree instead of routing
/// through the standalone player's session state.
@MainActor
private struct HostedHeadphoneCorrectionCatalog: View {
    let onApply: (MobileEQSettings) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category: String?
    @State private var presets: [MobileAutoEqPreset] = []
    @State private var errorMessage: String?

    private let catalog = AutoEqCatalog.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search brand or model", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("hostHeadphoneCatalogSearch")
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        categoryButton("All", value: nil)
                        ForEach(catalog.categories(), id: \.self) { value in
                            categoryButton(value.capitalized, value: value)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 8)

                if !catalog.isAvailable {
                    ContentUnavailableView(
                        "Headphone Library Unavailable",
                        systemImage: "headphones",
                        description: Text("The bundled correction catalog could not be opened.")
                    )
                } else if presets.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(presets) { preset in
                        Button { select(preset) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.model).font(.body.weight(.medium)).foregroundStyle(.primary)
                                Text(preset.source).font(.caption).foregroundStyle(.secondary)
                                Text("\(preset.brand) · \(preset.category.capitalized) · \(preset.preampDb.formatted(.number.precision(.fractionLength(1)))) dB preamp")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("hostHeadphonePreset-\(preset.id)")
                        .contextMenu {
                            if let sourceURL = preset.sourceURL {
                                Link("Published Preset", destination: sourceURL)
                            }
                            if preset.dataLicense == "CC BY-SA 4.0",
                               let licenseURL = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/") {
                                Link("CC BY-SA 4.0", destination: licenseURL)
                            }
                        }
                    }
                    .listStyle(.plain)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Corrections are measurement-based starting points; fit and listening conditions vary.")
                    Link("AutoEq data · MIT License", destination: URL(string: "https://github.com/jaakkopasanen/AutoEq")!)
                    Link("OPRA supplemental data and attribution", destination: URL(string: "https://github.com/opra-project/OPRA")!)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .navigationTitle("Headphone Corrections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Headphone Corrections").font(.headline)
                        Text("\(catalog.totalCount.formatted()) offline profiles")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: refresh)
            .onChange(of: query) { _, _ in refresh() }
        }
    }

    private func categoryButton(_ title: String, value: String?) -> some View {
        let selected = value == category
        return Button(title) {
            category = value
            refresh()
        }
        .font(.caption.weight(selected ? .semibold : .regular))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(selected ? EqualizerEditor.accent.opacity(0.2) : Color(uiColor: .secondarySystemGroupedBackground),
                    in: Capsule())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func refresh() {
        presets = catalog.search(query, category: category)
    }

    private func select(_ preset: MobileAutoEqPreset) {
        errorMessage = nil
        do {
            onApply(try preset.settings())
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
