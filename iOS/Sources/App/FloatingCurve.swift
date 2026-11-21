import AVKit
import os
import SwiftUI

@MainActor @Observable
final class FloatingCurve: NSObject {
    let isSupported = AVPictureInPictureController.isPictureInPictureSupported()
    private(set) var isPossible = false
    private(set) var isActive = false
    private(set) var message: String?

    @ObservationIgnored private weak var player: PreviewPlayer?
    @ObservationIgnored private weak var layer: AVSampleBufferDisplayLayer?
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var possibilityObservation: NSKeyValueObservation?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private lazy var renderer = CurveVideoRenderer()
    @ObservationIgnored private var lastFrame: CurveVideoFrame?
    @ObservationIgnored private nonisolated let playerState = OSAllocatedUnfairLock(initialState: PreviewPlayer.State.idle)

    func attach(to layer: AVSampleBufferDisplayLayer, player: PreviewPlayer) {
        guard isSupported, self.layer !== layer else { return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        if self.player !== player {
            self.player = player
            observePlayback(of: player)
        }
        self.layer = layer
        self.controller = controller
        lastFrame = nil
        layer.videoGravity = .resizeAspect
        controller.delegate = self
        controller.requiresLinearPlayback = true
        possibilityObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] observed, change in
            let possible = change.newValue ?? false
            Task { @MainActor [weak observed] in
                guard let self, self.controller === observed else { return }
                self.isPossible = possible
            }
        }
        playbackChanged()
    }

    private func observePlayback(of player: PreviewPlayer) {
        withObservationTracking {
            _ = player.state
        } onChange: { [weak self, weak player] in
            Task { @MainActor in
                guard let self, let player, self.player === player else { return }
                self.observePlayback(of: player)
                self.playbackChanged()
            }
        }
    }

    private func playbackChanged() {
        let state = player?.state ?? .idle
        playerState.withLock { $0 = state }
        controller?.invalidatePlaybackState()
        if state == .idle, controller?.isPictureInPictureActive == true {
            controller?.stopPictureInPicture()
        }
        if state == .playing || state == .paused { enqueueFrame() }
    }

    func toggle() {
        guard let controller else { return }
        message = nil
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else if controller.isPictureInPicturePossible {
            enqueueFrame()
            controller.startPictureInPicture()
        }
    }

    private func enqueueFrame() {
        guard let player, let title = player.fileName, let layer else { return }
        let output = layer.sampleBufferRenderer
        if output.requiresFlushToResumeDecoding {
            output.flush()
            lastFrame = nil
        }
        guard output.isReadyForMoreMediaData else { return }
        let frame = CurveVideoFrame(title: title, settings: player.settings, sampleRate: player.sampleRate,
                                    progress: player.progress)
        guard frame != lastFrame, let sample = renderer.render(frame) else { return }
        output.enqueue(sample)
        lastFrame = frame
    }

    private func startFrames() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.enqueueFrame() }
        }
        timer.tolerance = 0.05
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopFrames() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }
}

extension FloatingCurve: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor [weak self, weak controller] in
            guard let self, self.controller === controller else { return }
            self.startFrames()
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor [weak self, weak controller] in
            guard let self, self.controller === controller else { return }
            self.isActive = true
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor [weak self, weak controller] in
            guard let self, self.controller === controller else { return }
            self.isActive = false
            self.stopFrames()
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor [weak self, weak controller] in
            guard let self, self.controller === controller else { return }
            self.message = "The floating curve couldn’t open. Try again while audio is playing."
            self.stopFrames()
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
                                                completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}

extension FloatingCurve: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        Task { @MainActor [weak self] in
            guard let player = self?.player else { return }
            if playing {
                await player.play()
            } else {
                player.pause()
            }
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        let state = playerState.withLock { $0 }
        if state == .playing || state == .paused { return CMTimeRange(start: .zero, duration: .positiveInfinity) }
        return .invalid
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        playerState.withLock { $0 != .playing }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                                completion: @escaping () -> Void) {
        completion()
    }
}

struct FloatingCurvePreview: UIViewRepresentable {
    let player: PreviewPlayer
    let curve: FloatingCurve

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.attach = { [weak player, weak curve] layer in
            if let player { curve?.attach(to: layer, player: player) }
        }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
        var attach: ((AVSampleBufferDisplayLayer) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, let display = layer as? AVSampleBufferDisplayLayer else { return }
            attach?(display)
        }
    }
}
