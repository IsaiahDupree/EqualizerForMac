import AVFAudio

struct PlaybackResumeSegment: Equatable {
    let startingFrame: AVAudioFramePosition
    let frameCount: AVAudioFrameCount

    init?(totalFrames: AVAudioFramePosition, progress: Double) {
        guard totalFrames > 0, progress.isFinite else { return nil }
        let normalizedProgress = min(max(progress, 0), 1)
        let start = min(AVAudioFramePosition(Double(totalFrames) * normalizedProgress), totalFrames)
        let remaining = totalFrames - start
        guard remaining > 0, remaining <= AVAudioFramePosition(AVAudioFrameCount.max) else { return nil }
        startingFrame = start
        frameCount = AVAudioFrameCount(remaining)
    }

    func progress(renderedFrames: AVAudioFramePosition, totalFrames: AVAudioFramePosition) -> Double {
        guard totalFrames > 0 else { return 0 }
        let position = Double(startingFrame) + Double(max(0, renderedFrames))
        return min(max(position / Double(totalFrames), 0), 1)
    }
}

enum PlaybackRouteReconnectPolicy {
    static func isReconnectable(portType: AVAudioSession.Port) -> Bool {
        switch portType {
        case .carAudio, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            return true
        default:
            return false
        }
    }

    static func shouldResume(expectedOutputID: String?, currentOutputID: String?) -> Bool {
        guard let expectedOutputID, !expectedOutputID.isEmpty,
              let currentOutputID, !currentOutputID.isEmpty else { return false }
        return expectedOutputID == currentOutputID
    }

    /// Preserve the route identity across an engine format notification. The
    /// route-change notification can be delivered after the engine has already
    /// been reconfigured, so it may not be available to seed reconnection state.
    static func configurationChangeReconnectID(pendingOutputID: String?,
                                               activeOutputID: String?) -> String? {
        if let pendingOutputID, !pendingOutputID.isEmpty { return pendingOutputID }
        guard let activeOutputID, !activeOutputID.isEmpty else { return nil }
        return activeOutputID
    }
}
