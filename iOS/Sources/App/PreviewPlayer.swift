import AudioToolbox
import AVFAudio
import Observation

@MainActor @Observable
final class PreviewPlayer {
    enum State { case idle, starting, playing }

    private(set) var state = State.idle
    private(set) var fileName: String?
    private(set) var sampleRate = 48_000.0
    private(set) var outputName: String?
    var error: String?

    @ObservationIgnored private var selected: SelectedAudio?
    @ObservationIgnored private var graph: PlaybackGraph?
    @ObservationIgnored private var playRequest: UUID?
    @ObservationIgnored private var sessionActive = false
    @ObservationIgnored private var settings = MobileEQSettings()
    @ObservationIgnored private let session = AVAudioSession.sharedInstance()

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
            try session.setActive(true)
            sessionActive = true
            try graph.engine.start()
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

    func stop() {
        playRequest = nil
        graph?.player.stop()
        graph?.engine.stop()
        graph = nil
        if sessionActive {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
        outputName = nil
        state = .idle
    }

    func handleInterruption(_ notification: Notification) {
        guard state != .idle,
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
        guard let engine = notification.object as? AVAudioEngine, engine === graph?.engine, state == .playing else { return }
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

    init(effect: AVAudioUnit, format: AVAudioFormat) throws {
        guard let tree = effect.auAudioUnit.parameterTree else { throw CocoaError(.featureUnsupported) }
        self.effect = effect
        self.tree = tree
        engine.attach(player)
        engine.attach(effect)
        engine.connect(player, to: effect, format: format)
        engine.connect(effect, to: engine.mainMixerNode, format: format)
    }

    func apply(_ settings: MobileEQSettings, changedFrom previous: MobileEQSettings? = nil) {
        for parameter in tree.allParameters {
            let value = settings.value(at: parameter.address)
            if previous?.value(at: parameter.address) != value { parameter.value = value }
        }
    }
}
