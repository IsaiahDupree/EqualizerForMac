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
    }

    // EQ state (control plane)
    var bands: [EQBand] = Presets.flat
    var preampDb: Float = 0
    var bypassed = false

    // UI state
    var isRunning = false
    var outputDeviceName = "—"
    var errorMessage: String?
    /// Name of the loaded headphone/AutoEq preset, if any (shown in the header).
    var activePresetName: String?

    private var sampleRate: Double { tap?.tapFormat?.mSampleRate ?? 48_000 }

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
        eq.update(bands: bands, preampDb: preampDb, bypassed: bypassed, sampleRate: sampleRate)
    }

    func setGain(_ gain: Float, at index: Int) {
        guard bands.indices.contains(index) else { return }
        bands[index].gain = gain
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

    func resetFlat() {
        activePresetName = nil
        apply(Presets.flat)
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

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}
