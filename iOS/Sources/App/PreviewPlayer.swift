import AudioToolbox
import AVFAudio
import Observation

@MainActor @Observable
final class PreviewPlayer {
    enum State: Sendable { case idle, starting, playing, paused }

    private(set) var state = State.idle
    private(set) var fileName: String?
    private(set) var sampleRate = 48_000.0
    private(set) var outputName: String?
    var error: String?

    @ObservationIgnored private var selected: SelectedAudio?
    @ObservationIgnored private var graph: PlaybackGraph?
    @ObservationIgnored private var playRequest: UUID?
    @ObservationIgnored private var sessionActive = false
    @ObservationIgnored private(set) var settings = MobileEQSettings()
    @ObservationIgnored private var pausedProgress = 0.0
    @ObservationIgnored private let session = AVAudioSession.sharedInstance()
    @ObservationIgnored private var analysis: AudioAnalysisMonitor?

    func readAnalysis() -> AudioAnalysisFrame? {
        guard state == .playing, let capture = graph?.capture else { return nil }
        if analysis == nil { analysis = AudioAnalysisMonitor() }
        return analysis?.read(capture.pointer)
    }

    func select(_ url: URL) {
        do {
            let selection = try SelectedAudio(url: url)
            stop()
            selected = selection
            fileName = url.lastPathComponent
            sampleRate = selection.file.processingFormat.sampleRate
            error = nil
        } catch {
            self.error = "Choose a readable mono or stereo audio file from Files."
        }
    }

    func apply(_ settings: MobileEQSettings) {
        let previous = self.settings
        self.settings = settings
        graph?.apply(settings, changedFrom: previous)
    }

    func play() async {
        if state == .paused {
            resume()
            return
        }
        guard let selected, state == .idle else { return }
        let request = UUID()
        playRequest = request
        state = .starting
        error = nil

        do {
            let effect = try await AVAudioUnit.instantiate(with: MobileEQ.component, options: .loadOutOfProcess)
            guard playRequest == request else { return }
            let graph = try PlaybackGraph(effect: effect, format: selected.file.processingFormat)
            graph.apply(settings)
            self.graph = graph

            try session.setCategory(.playback, mode: .default)
            try startEngine(graph)
            graph.player.scheduleFile(selected.file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.playRequest == request else { return }
                    self.stop()
                }
            }
            graph.player.play()
            outputName = session.currentRoute.outputs.first?.portName
            state = .playing
        } catch {
            guard playRequest == request else { return }
            stop()
            self.error = "Playback couldn’t start. Try another audio file or reopen Sonance EQ."
        }
    }

    func pause() {
        guard state == .playing, let graph else { return }
        pausedProgress = progress
        graph.player.pause()
        graph.engine.pause()
        state = .paused
        outputName = nil
        deactivateSession()
        analysis?.reset()
    }

    var progress: Double {
        if state == .paused { return pausedProgress }
        guard let file = selected?.file, let node = graph?.player,
              let nodeTime = node.lastRenderTime, let playhead = node.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        let elapsed = Double(playhead.sampleTime) / playhead.sampleRate
        return min(max(elapsed / duration, 0), 1)
    }

    private func resume() {
        guard let graph else { return }
        do {
            try startEngine(graph)
            graph.player.play()
            outputName = session.currentRoute.outputs.first?.portName
            state = .playing
        } catch {
            stop()
            self.error = "Playback couldn’t resume. Tap Play to start the file again."
        }
    }

    private func startEngine(_ graph: PlaybackGraph) throws {
        try session.setActive(true)
        sessionActive = true
        try graph.engine.start()
    }

    func stop() {
        playRequest = nil
        graph?.player.stop()
        graph?.removeAnalysisTap()
        graph?.engine.stop()
        graph = nil
        analysis?.reset()
        deactivateSession()
        outputName = nil
        state = .idle
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }

    func handleInterruption(_ notification: Notification) {
        guard state == .playing || state == .starting,
              notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue
        else { return }
        stop()
    }

    func handleRouteChange(_ notification: Notification) {
        guard state == .playing else { return }
        let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
            stop()
            error = "The audio output disconnected. Tap Play to use the current output."
        } else {
            outputName = session.currentRoute.outputs.first?.portName
        }
    }

    func handleConfigurationChange(_ notification: Notification) {
        guard state == .playing || state == .paused,
              let engine = notification.object as? AVAudioEngine, engine === graph?.engine else { return }
        stop()
        error = "The audio output changed. Tap Play to restart playback."
    }
}

private final class SelectedAudio {
    let file: AVAudioFile
    private let url: URL
    private let scoped: Bool

    init(url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard file.length > 0, (1...2).contains(format.channelCount),
                  (8_000...192_000).contains(format.sampleRate) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            self.file = file
            self.url = url
            self.scoped = scoped
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}

private final class PlaybackGraph {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    private let effect: AVAudioUnit
    private let tree: AUParameterTree
    let capture = PlayerAnalysisCapture()

    init(effect: AVAudioUnit, format: AVAudioFormat) throws {
        guard let tree = effect.auAudioUnit.parameterTree else { throw CocoaError(.featureUnsupported) }
        self.effect = effect
        self.tree = tree
        engine.attach(player)
        engine.attach(effect)
        engine.connect(player, to: effect, format: format)
        engine.connect(effect, to: engine.mainMixerNode, format: format)
        if let capture {
            effect.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
                guard let data = buffer.floatChannelData, !buffer.format.isInterleaved else { return }
                let right = buffer.format.channelCount == 2 ? data[1] : nil
                SonanceAnalysisPush(capture.pointer, data[0], right, buffer.frameLength, buffer.format.sampleRate)
            }
        }
    }

    func removeAnalysisTap() {
        if capture != nil { effect.removeTap(onBus: 0) }
    }

    func apply(_ settings: MobileEQSettings, changedFrom previous: MobileEQSettings? = nil) {
        settings.apply(to: tree, changedFrom: previous)
    }
}

// The tap owns the producer and the main actor owns the reader. The C capture coordinates their access.
private final class PlayerAnalysisCapture: @unchecked Sendable {
    let pointer: OpaquePointer

    init?() {
        guard let pointer = SonanceAnalysisCreate() else { return nil }
        self.pointer = pointer
    }

    deinit { SonanceAnalysisDestroy(pointer) }
}
