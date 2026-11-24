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
}
