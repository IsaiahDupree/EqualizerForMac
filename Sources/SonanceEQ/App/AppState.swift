import AppKit
import Foundation
import OSLog

@MainActor
@Observable
final class AppState {
    let eq = EQEngine()
    let permission = AudioRecordingPermission()

    private var tap: SystemAudioTap?
    private let log = Logger(subsystem: kSubsystem, category: "AppState")

    // EQ state (control plane)
    var bands: [EQBand] = Presets.flat
    var preampDb: Float = 0
    var bypassed = false

    // UI state
    var isRunning = false
    var outputDeviceName = "—"
    var errorMessage: String?

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

    func resetFlat() { apply(Presets.flat) }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}
