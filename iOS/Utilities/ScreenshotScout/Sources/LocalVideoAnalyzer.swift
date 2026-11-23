import AVFoundation
import CryptoKit
import Foundation

enum LocalVideoAnalyzer {
    static func sha256(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func process(url: URL) async throws -> ProcessedVideo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw LibraryError.unreadableVideo }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)

        let sampleFractions: [Double] = [0.08, 0.25, 0.50, 0.75, 0.92]
        var frames: [ProcessedVideoFrame] = []
        for fraction in sampleFractions {
            try Task.checkCancellation()
            let seconds = min(max(duration * fraction, 0), max(0, duration - 0.05))
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            var actualTime = CMTime.invalid
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: &actualTime) else { continue }
            let analyzed = try LocalImageAnalyzer.process(frame: cgImage)
            frames.append(
                ProcessedVideoFrame(
                    timeSeconds: CMTimeGetSeconds(actualTime),
                    jpegData: analyzed.jpegData,
                    recognizedText: analyzed.recognizedText,
                    labels: analyzed.labels
                )
            )
        }

        try Task.checkCancellation()
        guard !frames.isEmpty else { throw LibraryError.noVideoFrames }
        return ProcessedVideo(durationSeconds: duration, frames: frames)
    }
}
