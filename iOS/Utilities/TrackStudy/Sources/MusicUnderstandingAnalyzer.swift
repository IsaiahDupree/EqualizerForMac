import AVFoundation
import Foundation

#if compiler(>=6.4) && canImport(MusicUnderstanding)
import MusicUnderstanding
#endif

enum MusicUnderstandingAnalyzer {
    static var isAvailable: Bool {
        #if compiler(>=6.4) && canImport(MusicUnderstanding)
        if #available(iOS 27.0, *) { return true }
        #endif
        return false
    }

    static func analyze(fileURL: URL) async throws -> MusicAnalysis {
        #if compiler(>=6.4) && canImport(MusicUnderstanding)
        guard #available(iOS 27.0, *) else {
            throw TrackStudyError.musicUnderstandingRequiresIOS27
        }

        let asset = AVURLAsset(
            url: fileURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        let session = try await MusicUnderstandingSession(asset: asset)
        let result = try await session.analyze(for: [.rhythm, .key, .structure, .pace])
        let keySpans = (result.key?.ranges ?? []).map { value in
            KeySpan(
                key: "\(value.value.tonic.rawValue) \(value.value.mode.rawValue)",
                startSeconds: value.range.start.seconds,
                durationSeconds: value.range.duration.seconds
            )
        }
        let sectionSpans = (result.structure?.sections ?? []).map { range in
            TimeSpan(startSeconds: range.start.seconds, durationSeconds: range.duration.seconds)
        }
        let paceSpans = (result.pace?.ranges ?? []).map { value in
            PaceSpan(
                startSeconds: value.range.start.seconds,
                durationSeconds: value.range.duration.seconds,
                pace: value.value
            )
        }
        return MusicAnalysis(
            tempoBPM: result.rhythm?.beatsPerMinute.map { Int($0.rounded()) },
            keySpans: keySpans,
            sectionSpans: sectionSpans,
            paceSpans: paceSpans
        )
        #else
        throw TrackStudyError.musicUnderstandingRequiresCurrentSDK
        #endif
    }
}
