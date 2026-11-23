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

    static func makeOperation(fileURL: URL) async throws -> any MusicAnalysisOperation {
        #if compiler(>=6.4) && canImport(MusicUnderstanding)
        guard #available(iOS 27.0, *) else {
            throw TrackStudyError.musicUnderstandingRequiresIOS27
        }

        let asset = AVURLAsset(
            url: fileURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        let session = try await MusicUnderstandingSession(asset: asset)
        return MusicUnderstandingOperation(session: session)
        #else
        throw TrackStudyError.musicUnderstandingRequiresCurrentSDK
        #endif
    }
}

protocol MusicAnalysisOperation: Sendable {
    func analyze() async throws -> MusicAnalysis
    func cancel() async
}

#if compiler(>=6.4) && canImport(MusicUnderstanding)
@available(iOS 27.0, *)
private actor MusicUnderstandingOperation: MusicAnalysisOperation {
    private let session: MusicUnderstandingSession

    init(session: MusicUnderstandingSession) {
        self.session = session
    }

    func analyze() async throws -> MusicAnalysis {
        let result = try await session.analyze(for: [
            .rhythm, .key, .structure, .pace, .instrumentActivity, .loudness
        ])
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
        let instrumentSpans = (result.instrumentActivity?.ranges ?? [:])
            .flatMap { instrument, ranges in
                ranges.map { range in
                    InstrumentSpan(
                        instrument: instrument.rawValue,
                        startSeconds: range.start.seconds,
                        durationSeconds: range.duration.seconds
                    )
                }
            }
            .sorted {
                if $0.startSeconds == $1.startSeconds {
                    return $0.instrument < $1.instrument
                }
                return $0.startSeconds < $1.startSeconds
            }
        return MusicAnalysis(
            tempoBPM: result.rhythm?.beatsPerMinute.map { Int($0.rounded()) },
            keySpans: keySpans,
            sectionSpans: sectionSpans,
            paceSpans: paceSpans,
            instrumentSpans: instrumentSpans,
            integratedLoudnessLUFS: result.loudness.map { Double($0.integrated.value) },
            peakDecibels: result.loudness.map { Double($0.peak.value) }
        )
    }

    func cancel() async {
        await session.cancel()
    }
}
#endif
