import AppKit
import Foundation
import OSLog

@MainActor
@Observable
final class AppState {
    let eq = EQEngine()
    let permission = AudioRecordingPermission()
    let license = PurchaseManager()

    private var tap: SystemAudioTap?
    private let log = Logger(subsystem: kSubsystem, category: "AppState")

    init() {
        license.start()
        if CommandLine.arguments.contains("--demo") {
            // Presentation/screenshot state: a shaped curve with Pro unlocked (no locks).
            license.mockUnlock()
            bands = Presets.loudness
            activePresetName = "Loudness"
        }
    }

    /// Which EQ chain the editor is shaping in Mid-Side mode.
    enum ChannelTarget { case mid, side }

    // EQ state (control plane)
    var bands: [EQBand] = Presets.flat       // Mid (or the single curve in plain stereo)
    var sideBands: [EQBand] = []             // Side chain (only used in Mid-Side mode)
    var preampDb: Float = 0
    var bypassed = false
    /// Linear-phase (FIR) mode. Off = minimum-phase IIR (zero added latency).
    var linearPhase = false
    /// Mid-Side mode: EQ the mono (Mid) and stereo-difference (Side) signals separately.
    var midSideEnabled = false
    /// Which chain the editor curve is currently shaping.
    var editTarget: ChannelTarget = .mid

    /// The band set the editor is currently shaping (Mid or Side).
    var activeBands: [EQBand] {
        get { editTarget == .side ? sideBands : bands }
        set { if editTarget == .side { sideBands = newValue } else { bands = newValue } }
    }

    // Per-app EQ (Pro)
    var eqTarget: EQTarget = .allApps
    var availableApps: [AudioApp] = []

    // UI state
    var isRunning = false
    var outputDeviceName = "—"
    var errorMessage: String?
    var showingAbout = false
    /// Name of the loaded headphone/AutoEq preset, if any (shown in the header).
    var activePresetName: String?

    private var sampleRate: Double { tap?.tapFormat?.mSampleRate ?? 48_000 }

    /// Sample rate to draw the response curve against (live tap rate, or 48 kHz when stopped).
    var sampleRateHz: Double { sampleRate }

    // MARK: Run control

    func toggle() { isRunning ? stop() : start() }

    func start() {
        errorMessage = nil
        switch permission.status {
        case .authorized:
            reallyStart()
        case .unknown:
            permission.request { [weak self] granted in
                guard let self else { return }
                if granted { self.reallyStart() }
                else { self.errorMessage = "Audio Capture permission was denied." }
            }
        case .denied:
            errorMessage = "Enable Audio Capture for Sonance EQ in System Settings → Privacy & Security."
        }
    }

    private func reallyStart() {
        pushSettings()
        let tap = SystemAudioTap(eq: eq)
        tap.onRebuild = { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case let .success(name):
                    self.outputDeviceName = name
                case let .failure(error):
                    self.isRunning = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
        tap.target = eqTarget
        do {
            try tap.start()
            self.tap = tap
            self.outputDeviceName = tap.outputDeviceName
            self.isRunning = true
        } catch {
            self.errorMessage = error.localizedDescription
            log.error("Start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        tap?.stop()
        tap = nil
        isRunning = false
    }

    // MARK: EQ edits

    /// Push the current band/preamp/bypass state to the audio engine.
    func pushSettings() {
        eq.update(bands: bands, sideBands: sideBands, preampDb: preampDb, bypassed: bypassed,
                  sampleRate: sampleRate, linearPhase: linearPhase, midSide: midSideEnabled)
    }

    /// Toggle Mid-Side mode. Seeds a flat Side curve the first time it's enabled.
    func setMidSide(_ on: Bool) {
        midSideEnabled = on
        if on, sideBands.isEmpty { sideBands = Presets.flat }
        if !on { editTarget = .mid }
        pushSettings()
    }

    /// Added latency from linear-phase mode (0 in minimum-phase mode).
    var latencyMs: Double {
        linearPhase ? Double(FIRProcessor.length / 2) / sampleRateHz * 1000 : 0
    }

    /// Add a new parametric band (peaking, 1 kHz, flat) to the active chain. Returns its id to select it.
    @discardableResult
    func addBand() -> UUID? {
        guard activeBands.count < EQEngine.maxBands else { return nil }
        let band = EQBand(frequency: 1000, gain: 0, q: 1.0, type: .peaking)
        activeBands.append(band)
        activePresetName = nil
        pushSettings()
        return band.id
    }

    func removeBand(id: UUID) {
        activeBands.removeAll { $0.id == id }
        activePresetName = nil
        pushSettings()
    }

    func apply(_ preset: [EQBand]) {
        bands = preset
        pushSettings()
    }

    /// Load an AutoEq headphone correction: its parametric bands + its safety preamp.
    func applyAutoEq(_ preset: AutoEqPreset) {
        let newBands = preset.bands()
        guard !newBands.isEmpty else { return }
        bands = newBands
        preampDb = preset.preampDb
        activePresetName = preset.displayName
        pushSettings()
    }

    /// Reset the chain currently being edited to flat.
    func resetFlat() {
        activePresetName = nil
        activeBands = Presets.flat
        pushSettings()
    }

    // MARK: Import / Export
    // Dev builds use AppKit panels directly (not sandboxed). The Mac App Store build will swap these
    // for SwiftUI `.fileExporter`/`.fileImporter` so file access works under the sandbox.

    func exportCurrentPreset() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(activePresetName ?? "My EQ").sonanceeq.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let file = PresetFile(name: activePresetName ?? "My EQ", preampDb: preampDb, bands: bands)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(file).write(to: url)
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try JSONDecoder().decode(PresetFile.self, from: Data(contentsOf: url))
            let imported = file.eqBands()
            guard !imported.isEmpty else { errorMessage = "That file has no EQ bands."; return }
            bands = imported
            preampDb = file.preampDb
            activePresetName = file.name
            pushSettings()
        } catch {
            errorMessage = "Import failed: not a Sonance EQ preset."
        }
    }

    // MARK: Per-app EQ

    /// Refresh the list of apps currently producing audio.
    func refreshApps() { availableApps = AudioProcesses.runningOutputApps() }

    /// Human-readable description of the current target (for the menu label).
    var targetLabel: String {
        switch eqTarget {
        case .allApps:
            return "All Apps"
        case let .apps(ids):
            if ids.isEmpty { return "All Apps" }
            let names = availableApps.filter { ids.contains($0.bundleID) }.map(\.name)
            let shown = names.isEmpty ? Array(ids) : names
            return shown.count == 1 ? shown[0] : "\(shown.count) apps"
        }
    }

    func isAppSelected(_ bundleID: String) -> Bool {
        if case let .apps(ids) = eqTarget { return ids.contains(bundleID) }
        return false
    }

    func setAllApps() {
        eqTarget = .allApps
        tap?.retarget(eqTarget)
    }

    /// Toggle one app in the target set; an empty set falls back to All Apps.
    func toggleApp(_ bundleID: String) {
        var ids: Set<String> = { if case let .apps(s) = eqTarget { return s } else { return [] } }()
        if ids.contains(bundleID) { ids.remove(bundleID) } else { ids.insert(bundleID) }
        eqTarget = ids.isEmpty ? .allApps : .apps(ids)
        tap?.retarget(eqTarget)
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}
