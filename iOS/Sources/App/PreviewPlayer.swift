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
    private(set) var currentOutput: PlaybackOutput?
    private(set) var routeFormat = PlaybackRouteFormat(sampleRateHz: 0, outputChannels: 0,
                                                       ioBufferDurationSeconds: 0)
    var error: String?

    @ObservationIgnored private var selected: SelectedAudio?
    @ObservationIgnored private var graph: PlaybackGraph?
    @ObservationIgnored private var playRequest: UUID?
    @ObservationIgnored private var segmentRequest: UUID?
    @ObservationIgnored private var sessionActive = false
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var reconnectOutputID: String?
    @ObservationIgnored private var activeReconnectableOutputID: String?
    @ObservationIgnored private var activeSegment: PlaybackResumeSegment?
    @ObservationIgnored private(set) var settings = MobileEQSettings()
    @ObservationIgnored private var pausedProgress = 0.0
    @ObservationIgnored private let session = AVAudioSession.sharedInstance()
    @ObservationIgnored private var analysis: AudioAnalysisMonitor?
    @ObservationIgnored private var outputCorrections: [String: OutputCorrection] = [:]
    @ObservationIgnored private var sleepTimerTask: Task<Void, Never>?
    private(set) var sleepTimerMinutes: Int?
    private static let bypassedCorrection = MobileEQSettings(bands: [], bypassed: true)

    func readAnalysis() -> AudioAnalysisFrame? {
        guard state == .playing, let capture = graph?.capture else { return nil }
        if analysis == nil { analysis = AudioAnalysisMonitor() }
        return analysis?.read(capture.pointer)
    }

    func readRenderMetrics() -> AudioRenderMetrics? {
        graph?.renderMetrics
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

    func applyOutputCorrections(_ corrections: [String: OutputCorrection]) {
        outputCorrections = corrections
        refreshOutput()
    }

    func setSleepTimer(minutes: Int?) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerMinutes = minutes
        guard let minutes else { return }

        sleepTimerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.error = "Sleep timer ended playback."
            self.stop()
        }
    }

    func refreshOutput() {
        routeFormat = PlaybackRouteFormat(sampleRateHz: session.sampleRate,
                                          outputChannels: session.outputNumberOfChannels,
                                          ioBufferDurationSeconds: session.ioBufferDuration)
        let outputs = session.currentRoute.outputs
        if outputs.count == 1, let port = outputs.first, !port.uid.isEmpty {
            currentOutput = PlaybackOutput(id: port.uid, name: port.portName)
        } else {
            currentOutput = nil
        }
        if state == .playing { outputName = outputs.first?.portName }

        let assignment = currentOutput.flatMap { outputCorrections[$0.id] }
        let correction = assignment.flatMap { $0.enabled ? $0.settings : nil } ?? Self.bypassedCorrection
        graph?.applyCorrection(correction)
    }

    func play() async {
        if state == .paused {
            resumeAfterInterruption = false
            reconnectOutputID = nil
            if graph != nil {
                resume()
            } else {
                await startPlayback(fromProgress: pausedProgress)
            }
            return
        }
        guard selected != nil, state == .idle else { return }
        await startPlayback(fromProgress: 0)
    }

    private func startPlayback(fromProgress startProgress: Double) async {
        guard let selected else { return }
        let request = UUID()
        playRequest = request
        state = .starting
        error = nil

        guard let segment = PlaybackResumeSegment(totalFrames: selected.file.length, progress: startProgress) else {
            playRequest = nil
            state = .idle
            error = "Playback couldn’t resume from this position. Tap Play to restart the file."
            return
        }
        activeSegment = segment

        do {
            let effect = try await AVAudioUnit.instantiate(with: MobileEQ.component, options: .loadOutOfProcess)
            guard playRequest == request else { return }
            let correction = try await AVAudioUnit.instantiate(with: MobileEQ.component, options: .loadOutOfProcess)
            guard playRequest == request else { return }
            let graph = try PlaybackGraph(effect: effect, correction: correction, format: selected.file.processingFormat)
            graph.apply(settings)
            self.graph = graph

            try session.setCategory(.playback, mode: .default)
            try startEngine(graph)
            schedule(segment, in: graph, request: request)
            graph.player.play()
            outputName = session.currentRoute.outputs.first?.portName
            state = .playing
            rememberReconnectableOutput()
        } catch {
            guard playRequest == request else { return }
            stop()
            self.error = "Playback couldn’t start. Try another audio file or reopen Sonance EQ."
        }
    }

    func pause() {
        guard state == .playing, let graph else { return }
        pausedProgress = progress
        reconnectOutputID = nil
        activeReconnectableOutputID = nil
        graph.player.pause()
        graph.engine.pause()
        state = .paused
        outputName = nil
        deactivateSession()
        analysis?.reset()
        refreshOutput()
    }

    var progress: Double {
        if state == .paused { return pausedProgress }
        guard let file = selected?.file, let node = graph?.player,
              let nodeTime = node.lastRenderTime, let playhead = node.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        return activeSegment?.progress(renderedFrames: playhead.sampleTime, totalFrames: file.length) ?? 0
    }

    var duration: TimeInterval {
        guard let file = selected?.file else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    func seek(to requestedProgress: Double) {
        guard requestedProgress.isFinite, (state == .playing || state == .paused),
              let selected else { return }
        let target = min(max(requestedProgress, 0), 1)
        guard target < 1,
              let segment = PlaybackResumeSegment(totalFrames: selected.file.length, progress: target) else {
            stop()
            return
        }
        pausedProgress = target
        activeSegment = segment
        guard let graph, let request = playRequest else { return }
        graph.player.stop()
        schedule(segment, in: graph, request: request)
        if state == .playing { graph.player.play() }
    }

    private func schedule(_ segment: PlaybackResumeSegment, in graph: PlaybackGraph, request: UUID) {
        let segmentRequest = UUID()
        self.segmentRequest = segmentRequest
        guard let file = selected?.file else { return }
        graph.player.scheduleSegment(file, startingFrame: segment.startingFrame,
                                    frameCount: segment.frameCount, at: nil,
                                    completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playRequest == request,
                      self.segmentRequest == segmentRequest else { return }
                self.stop()
            }
        }
    }

    private func resume() {
        resume(activateSession: true)
    }

    private func resume(activateSession: Bool) {
        guard let graph else { return }
        do {
            try startEngine(graph, activateSession: activateSession)
            graph.player.play()
            outputName = session.currentRoute.outputs.first?.portName
            state = .playing
            rememberReconnectableOutput()
        } catch {
            stop()
            self.error = "Playback couldn’t resume. Tap Play to start the file again."
        }
    }

    private func startEngine(_ graph: PlaybackGraph, activateSession: Bool = true) throws {
        if activateSession {
            try session.setActive(true)
            sessionActive = true
        }
        refreshOutput()
        try graph.engine.start()
    }

    func stop() {
        playRequest = nil
        segmentRequest = nil
        resumeAfterInterruption = false
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerMinutes = nil
        reconnectOutputID = nil
        activeReconnectableOutputID = nil
        pausedProgress = 0
        activeSegment = nil
        graph?.player.stop()
        graph?.removeAnalysisTap()
        graph?.engine.stop()
        graph = nil
        analysis?.reset()
        deactivateSession()
        outputName = nil
        state = .idle
        refreshOutput()
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }

    func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
        if rawType == AVAudioSession.InterruptionType.began.rawValue {
            pauseForSystemInterruption()
        } else if rawType == AVAudioSession.InterruptionType.ended.rawValue {
            guard resumeAfterInterruption else { return }
            resumeAfterInterruption = false
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            guard AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) else { return }
            resume()
        }
    }

    @available(iOS 27.0, *)
    func handleSystemDeactivation(_ notification: Notification) {
        guard let context = notification.userInfo?[AVAudioSession.deactivationContextKey]
                as? AVAudioSession.DeactivationContext,
              context.source == .system else { return }
        pauseForSystemInterruption()
    }

    @available(iOS 27.0, *)
    func handleResumptionRecommendation(_ notification: Notification) {
        guard resumeAfterInterruption,
              let context = notification.userInfo?[AVAudioSession.resumptionContextKey]
                as? AVAudioSession.ResumptionContext else { return }
        switch context.recommendation {
        case .shouldResume:
            Task { [weak self] in
                guard let self else { return }
                do {
                    _ = try await self.session.activate()
                    guard self.resumeAfterInterruption else { return }
                    self.resumeAfterInterruption = false
                    self.resume(activateSession: false)
                } catch {
                    self.resumeAfterInterruption = false
                    self.error = "Playback remains paused because iOS couldn’t reactivate audio. Tap Play to resume."
                }
            }
        case .shouldNotResume:
            resumeAfterInterruption = false
        @unknown default:
            resumeAfterInterruption = false
        }
    }

    private func pauseForSystemInterruption() {
        if state == .starting {
            playRequest = nil
            state = .idle
            error = "Playback start was interrupted. Tap Play to try again."
            return
        }
        guard state == .playing, let graph else { return }
        pausedProgress = progress
        graph.player.pause()
        graph.engine.pause()
        state = .paused
        outputName = nil
        analysis?.reset()
        resumeAfterInterruption = true
    }

    func handleRouteChange(_ notification: Notification) {
        let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue &&
            (state == .playing || state == .starting || (state == .paused && resumeAfterInterruption)) {
            let previous = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
                as? AVAudioSessionRouteDescription
            let reconnectableOutput = previous?.outputs.first {
                PlaybackRouteReconnectPolicy.isReconnectable(portType: $0.portType)
            }
            resumeAfterInterruption = false
            parkForRouteChange(reconnectID: reconnectableOutput?.uid)
            if reconnectableOutput?.portType == .carAudio {
                error = "CarPlay disconnected. Playback is paused while Sonance waits for the same CarPlay route to return."
            } else if reconnectableOutput != nil {
                error = "Bluetooth disconnected. Playback is paused while Sonance waits for the same device to reconnect."
            } else {
                error = "The audio output changed. Playback is paused; tap Play to continue on the current output."
            }
        } else {
            refreshOutput()
            if reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue,
               let expectedID = reconnectOutputID,
               let output = session.currentRoute.outputs.first(where: {
                   PlaybackRouteReconnectPolicy.isReconnectable(portType: $0.portType)
               }),
               PlaybackRouteReconnectPolicy.shouldResume(expectedOutputID: expectedID,
                                                          currentOutputID: output.uid), state == .paused {
                reconnectOutputID = nil
                error = nil
                Task { await play() }
            }
        }
    }

    func handleConfigurationChange(_ notification: Notification) {
        guard state == .playing || state == .paused,
              let engine = notification.object as? AVAudioEngine, engine === graph?.engine else { return }
        let reconnectID = PlaybackRouteReconnectPolicy.configurationChangeReconnectID(
            pendingOutputID: reconnectOutputID,
            activeOutputID: state == .playing ? activeReconnectableOutputID : nil)
        parkForRouteChange(reconnectID: reconnectID)
        error = "The audio output changed. Playback is paused; tap Play to continue from here."
    }

    private func rememberReconnectableOutput() {
        activeReconnectableOutputID = session.currentRoute.outputs.first(where: {
            PlaybackRouteReconnectPolicy.isReconnectable(portType: $0.portType)
        })?.uid
    }

    private func parkForRouteChange(reconnectID: String?) {
        if state == .starting {
            playRequest = nil
            state = .idle
            return
        }
        if state == .playing { pausedProgress = progress }
        reconnectOutputID = reconnectID
        graph?.player.stop()
        graph?.removeAnalysisTap()
        graph?.engine.stop()
        graph = nil
        analysis?.reset()
        deactivateSession()
        outputName = nil
        state = .paused
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
    private let tree: AUParameterTree
    private let correction: AVAudioUnit
    private let correctionTree: AUParameterTree
    private var appliedCorrection: MobileEQSettings?
    let capture = PlayerAnalysisCapture()

    init(effect: AVAudioUnit, correction: AVAudioUnit, format: AVAudioFormat) throws {
        guard let tree = effect.auAudioUnit.parameterTree, let correctionTree = correction.auAudioUnit.parameterTree else {
            throw CocoaError(.featureUnsupported)
        }
        self.tree = tree
        self.correction = correction
        self.correctionTree = correctionTree
        engine.attach(player)
        engine.attach(effect)
        engine.attach(correction)
        engine.connect(player, to: effect, format: format)
        engine.connect(effect, to: correction, format: format)
        engine.connect(correction, to: engine.mainMixerNode, format: format)
        if let capture {
            correction.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
                guard let data = buffer.floatChannelData, !buffer.format.isInterleaved else { return }
                let right = buffer.format.channelCount == 2 ? data[1] : nil
                SonanceAnalysisPush(capture.pointer, data[0], right, buffer.frameLength, buffer.format.sampleRate)
            }
        }
    }

    func removeAnalysisTap() {
        if capture != nil { correction.removeTap(onBus: 0) }
    }

    func apply(_ settings: MobileEQSettings, changedFrom previous: MobileEQSettings? = nil) {
        settings.apply(to: tree, changedFrom: previous)
    }

    var renderMetrics: AudioRenderMetrics? { AudioRenderMetrics(parameterTree: tree) }

    func applyCorrection(_ settings: MobileEQSettings) {
        guard settings != appliedCorrection else { return }
        settings.apply(to: correctionTree, changedFrom: appliedCorrection)
        appliedCorrection = settings
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
