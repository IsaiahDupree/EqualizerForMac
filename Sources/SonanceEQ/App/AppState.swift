import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import OSLog

@MainActor
@Observable
final class AppState {
    let eq = EQEngine()
    let permission = AudioRecordingPermission()
    let license = PurchaseManager()
    let review = ReviewPrompter()
    let updates = AppUpdateChecker()
    let journey = ProductJourneyTracker()

    private var tap: SystemAudioTap?
    private var startGeneration: UInt64 = 0
    private var permissionRequestInFlight = false
    private var permissionDeadline: DispatchWorkItem?
    private let log = Logger(subsystem: kSubsystem, category: "AppState")
    private let diagnostics = DiagnosticsReporter()

    init() {
        diagnostics.start()
        license.tracker.onStorePurchaseSnapshot = { [weak journey] snapshot in
            journey?.observe(snapshot)
            Task { [weak journey] in await journey?.flush() }
        }
        license.tracker.onRecordedEvent = { [weak self] entry in
            guard let self, self.journey.optedIn, entry.store == "revenueCat",
                  entry.event == .purchaseCompleted || entry.event == .restoreCompleted else { return }
            Task { [weak self] in await self?.license.tracker.refreshStorePurchases() }
        }
        license.start()
        mixerEngine.onChannelFailure = { [weak self] bundleID, message in
            guard let self else { return }
            // The tap is already torn down (PerAppMixer dropped its own state before calling us) and the
            // app's audio has reverted to normal passthrough at the OS level. Reset the persisted channel
            // too, so the Mixer UI (mute icon / slider / output menu) doesn't keep showing a mute/volume/
            // routing that no longer reflects reality, and let the global EQ tap pick the app back up
            // (applyMixer() recomputes `excludedBundleIDs` from the now-updated active channels).
            self.mixer.reset(bundleID)
            self.applyMixer()
            self.errorMessage = EQText.format("Mixer: %@", message)
        }
        recorder.onFailure = { [weak self] message in
            guard let self else { return }
            self.finishRecordingUI()
            self.errorMessage = EQText.format("Recorder: %@", message)
        }
        #if DEBUG
        if LicenseConfig.isUnconfigured {
            // Local Debug build only (Xcode Run — never a distributed artifact): no real RevenueCat
            // account is wired up, so there's nothing to purchase. Ship permanently Pro-unlocked
            // instead of gating on the mock store, so launching the built .app directly (no CLI
            // flags) is already the unlocked, no-paywall experience for our own desktop use.
            //
            // Deliberately NOT applied to Release/Release-MAS: those are the configs the
            // distribution scripts (Tools/package_and_notarize.sh, Tools/build_mas.sh) and CI
            // (.github/workflows/release.yml) ship to real users. An unconfigured key there must
            // fall through to the normal locked-by-default mock store (see PurchaseManager.start()),
            // not an unconditional free unlock — see docs/RELEASE.md before shipping the Direct
            // channel: it still needs its own live RevenueCat key wired into project.yml the same
            // way Release-MAS already has one, or Direct-channel Pro stays unpurchasable for real.
            license.mockUnlock()
        }
        #endif
        if CommandLine.arguments.contains("--demo") {
            // Presentation/screenshot state: a shaped curve.
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

    // Per-app mixer (Pro): independent volume / mute / output routing per app
    let mixer = MixerState()
    // Internal (not private) so tests can drive `onChannelFailure` directly — see
    // MixerTests.channelFailureResetsMixerState — the exact reconciliation path this closure guards.
    let mixerEngine = PerAppMixer()
    var mixerEnabled = false
    var availableDevices: [AudioDevice] = []
    private var mixerDeviceListener: AudioObjectPropertyListenerBlock?

    // Audio recorder (Pro): capture system or per-app audio to a file
    private let recorder = AudioRecorder()
    var isRecording = false
    var recordingFormat: RecordingFormat = .wav
    var recordTarget: EQTarget = .allApps
    var recordingElapsed: Double = 0
    var lastRecordingURL: URL?
    private var recordingTimer: Timer?

    // UI state
    var isRunning = false
    private var audioFlowing = false
    private(set) var audioRouteFinishing = false
    // The notification drives observation; checking the tap also prevents an older queued
    // notification from displaying Active while a newer route is still waiting for callbacks.
    var isAudioFlowing: Bool { audioFlowing && tap?.isAudioFlowing == true }
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
        guard !isRunning else { return }
        guard !permissionRequestInFlight else { return }
        guard tap?.isFinishingOperation != true else { return }
        errorMessage = nil
        startGeneration &+= 1
        switch permission.status {
        case .authorized:
            reallyStart()
        case .unknown:
            let expectedGeneration = startGeneration
            permissionRequestInFlight = true
            audioRouteFinishing = true
            isRunning = true // pending intent keeps Stop available before any capture starts
            let deadline = DispatchWorkItem { [weak self] in
                guard let self, self.startGeneration == expectedGeneration,
                      self.permissionRequestInFlight, self.isRunning else { return }
                self.stop()
                self.errorMessage = EQText.string("Audio routing took too long. Check Audio Capture permission, then try again.")
            }
            permissionDeadline = deadline
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: deadline)
            permission.request { [weak self] granted in
                guard let self else { return }
                self.permissionRequestInFlight = false
                self.permissionDeadline?.cancel()
                self.permissionDeadline = nil
                self.audioRouteFinishing = self.tap?.isFinishingOperation ?? false
                guard self.startGeneration == expectedGeneration, self.isRunning else { return }
                self.isRunning = false
                if granted { self.reallyStart() }
                else { self.errorMessage = EQText.string("Audio Capture permission was denied.") }
            }
        case .denied:
            errorMessage = EQText.string("Enable Audio Capture for Sonance EQ in System Settings → Privacy & Security.")
        }
    }

    private func reallyStart() {
        guard !isRunning else { return }   // two pending permission grants may both return
        pushSettings()
        let tap = self.tap ?? SystemAudioTap(eq: eq)
        self.tap = tap
        audioFlowing = false
        tap.onAudioFlowChange = { [weak self, weak tap] in
            guard let self, let tap, self.tap === tap else { return }
            self.audioFlowing = tap.isAudioFlowing
            self.journey.observeAudioFlow(tap.isAudioFlowing)
            Task { [weak self] in await self?.journey.flush() }
            self.audioRouteFinishing = self.permissionRequestInFlight || tap.isFinishingOperation
        }
        tap.onRebuild = { [weak self, weak tap] result in
            guard let self, let tap, self.tap === tap else { return }
            self.audioFlowing = tap.isAudioFlowing
            self.audioRouteFinishing = self.permissionRequestInFlight || tap.isFinishingOperation
            switch result {
            case .success:
                guard tap.isRunning else { return }
                self.outputDeviceName = tap.outputDeviceName
            case let .failure(error):
                guard !tap.isRunning else { return }
                self.isRunning = false
                self.errorMessage = error.localizedDescription
            }
        }
        tap.target = eqTarget
        tap.excludedBundleIDs = mixerEnabled ? Set(mixer.activeChannels.map(\.bundleID)) : []
        do {
            try tap.start()
            self.tap = tap
            self.audioRouteFinishing = tap.isFinishingOperation
            self.outputDeviceName = tap.outputDeviceName
            self.isRunning = true
        } catch {
            self.errorMessage = error.localizedDescription
            log.error("Start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        startGeneration &+= 1
        permissionDeadline?.cancel()
        permissionDeadline = nil
        tap?.stop()
        // Retain its operation slot while an OS call/cleanup may still be pending.
        isRunning = false
        audioFlowing = false
        audioRouteFinishing = permissionRequestInFlight || tap?.isFinishingOperation == true
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
        review.positiveAction()
    }

    /// Load an AutoEq headphone correction: its parametric bands + its safety preamp.
    func applyAutoEq(_ preset: AutoEqPreset) {
        let newBands = preset.bands()
        guard !newBands.isEmpty else { return }
        bands = newBands
        preampDb = preset.preampDb
        activePresetName = preset.displayName
        pushSettings()
        review.positiveAction()
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
            errorMessage = EQText.format("Export failed: %@", error.localizedDescription)
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
            guard !imported.isEmpty else { errorMessage = EQText.string("That file has no EQ bands."); return }
            bands = imported
            preampDb = file.preampDb
            activePresetName = file.name
            pushSettings()
        } catch {
            errorMessage = EQText.string("Import failed: not a Sonance EQ preset.")
        }
    }

    // MARK: Per-app EQ

    /// Refresh the list of apps currently producing audio.
    func refreshApps() { availableApps = AudioProcesses.runningOutputApps() }

    /// Human-readable description of the current target (for the menu label).
    var targetLabel: String {
        switch eqTarget {
        case .allApps:
            return EQText.string("All Apps")
        case let .apps(ids):
            if ids.isEmpty { return EQText.string("All Apps") }
            let names = availableApps.filter { ids.contains($0.bundleID) }.map(\.name)
            let shown = names.isEmpty ? Array(ids) : names
            return shown.count == 1 ? shown[0] : EQText.format("%@ apps", shown.count.formatted())
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

    // MARK: Per-app mixer

    func refreshDevices() { availableDevices = AudioDevices.outputDevices() }

    /// Turn the mixer on/off. Off tears down all per-app mixer taps and stops excluding them from the EQ.
    func setMixerEnabled(_ on: Bool) {
        mixerEnabled = on
        if on {
            refreshApps(); refreshDevices(); applyMixer()
            installMixerDeviceListener()
        } else {
            mixerEngine.stopAll(); tap?.excludedBundleIDs = []
            removeMixerDeviceListener()
        }
    }

    private func applyMixer() {
        guard mixerEnabled else { return }
        mixerEngine.apply(mixer.activeChannels)
        // Keep the global EQ tap from also tapping the apps the mixer now owns.
        tap?.excludedBundleIDs = Set(mixer.activeChannels.map(\.bundleID))
    }

    // Apps routed to "Default Output" must follow when the user switches the system default (plug/unplug
    // headphones), or they keep playing to the old device. This listener rebuilds just the default-routed
    // mixer channels; pinned channels stay put. (The global EQ tap has its own rebuild in SystemAudioTap.)

    private func installMixerDeviceListener() {
        guard mixerDeviceListener == nil else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.mixerDefaultOutputChanged() }
        }
        mixerDeviceListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address,
                                            DispatchQueue.main, block)
    }

    private func removeMixerDeviceListener() {
        guard let block = mixerDeviceListener else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address,
                                               DispatchQueue.main, block)
        mixerDeviceListener = nil
    }

    private func mixerDefaultOutputChanged() {
        guard mixerEnabled else { return }
        refreshDevices()
        mixerEngine.handleDefaultOutputChange(mixer.activeChannels)
    }

    func setAppVolume(_ volume: Float, _ app: AudioApp) {
        mixer.setVolume(volume, for: app.bundleID, name: app.name); applyMixer()
    }

    func setAppMuted(_ muted: Bool, _ app: AudioApp) {
        mixer.setMuted(muted, for: app.bundleID, name: app.name); applyMixer()
    }

    func setAppOutput(_ uid: String?, _ app: AudioApp) {
        mixer.setOutput(uid, for: app.bundleID, name: app.name); applyMixer()
    }

    func resetAppChannel(_ app: AudioApp) {
        mixer.reset(app.bundleID); applyMixer()
    }

    // MARK: Audio recorder

    func toggleRecording() { isRecording ? stopRecording() : startRecording() }

    /// Ask where to save, then begin capturing the chosen target to disk.
    func startRecording() {
        guard !isRecording else { return }
        errorMessage = nil
        guard permission.status != .denied else {
            errorMessage = EQText.string("Enable Audio Capture for Sonance EQ in System Settings → Privacy & Security.")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [recordingFormat == .wav ? .wav : .mpeg4Audio]
        panel.nameFieldStringValue = "\(defaultRecordingBaseName).\(recordingFormat.fileExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try recorder.start(target: recordTarget, format: recordingFormat, url: url)
            isRecording = true
            recordingElapsed = 0
            lastRecordingURL = url
            startRecordingTimer()
        } catch {
            errorMessage = EQText.format("Recorder: %@", error.localizedDescription)
        }
    }

    func stopRecording() {
        let url = recorder.stop()
        finishRecordingUI()
        if let url { lastRecordingURL = url }
    }

    /// Reveal the most recent recording in Finder.
    func revealLastRecording() {
        guard let url = lastRecordingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// A timestamped default file name (no extension).
    private var defaultRecordingBaseName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Sonance Recording \(f.string(from: Date()))"
    }

    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.recordingElapsed = self.recorder.elapsedSeconds
            }
        }
    }

    /// Tear down UI/timer state after recording stops (whether by the user or a failure).
    private func finishRecordingUI() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingElapsed = recorder.elapsedSeconds
        isRecording = false
    }

    // Record-target selection (independent of the EQ target), mirroring the per-app EQ menu.
    var recordTargetLabel: String {
        switch recordTarget {
        case .allApps:
            return EQText.string("All Apps")
        case let .apps(ids):
            if ids.isEmpty { return EQText.string("All Apps") }
            let names = availableApps.filter { ids.contains($0.bundleID) }.map(\.name)
            let shown = names.isEmpty ? Array(ids) : names
            return shown.count == 1 ? shown[0] : EQText.format("%@ apps", shown.count.formatted())
        }
    }

    func isRecordAppSelected(_ bundleID: String) -> Bool {
        if case let .apps(ids) = recordTarget { return ids.contains(bundleID) }
        return false
    }

    func setRecordAllApps() { recordTarget = .allApps }

    func toggleRecordApp(_ bundleID: String) {
        var ids: Set<String> = { if case let .apps(s) = recordTarget { return s } else { return [] } }()
        if ids.contains(bundleID) { ids.remove(bundleID) } else { ids.insert(bundleID) }
        recordTarget = ids.isEmpty ? .allApps : .apps(ids)
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}
