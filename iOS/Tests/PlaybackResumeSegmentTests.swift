import AVFAudio
import XCTest
@testable import SonanceEQiOS

final class PlaybackResumeSegmentTests: XCTestCase {
    func testStartsAtBeginningWhenPlaybackIsFresh() {
        XCTAssertEqual(PlaybackResumeSegment(totalFrames: 48_000, progress: 0),
                       PlaybackResumeSegment(startingFrame: 0, frameCount: 48_000))
    }

    func testUsesSavedFractionOfFileForResume() {
        let segment = PlaybackResumeSegment(totalFrames: 96_000, progress: 0.375)
        XCTAssertEqual(segment, PlaybackResumeSegment(startingFrame: 36_000, frameCount: 60_000))
        XCTAssertEqual(segment?.progress(renderedFrames: 12_000, totalFrames: 96_000) ?? 0,
                       0.5, accuracy: 0.000_001)
    }

    func testClampsProgressToValidFileRange() {
        XCTAssertEqual(PlaybackResumeSegment(totalFrames: 12, progress: -1),
                       PlaybackResumeSegment(startingFrame: 0, frameCount: 12))
        XCTAssertNil(PlaybackResumeSegment(totalFrames: 12, progress: 1))
        XCTAssertNil(PlaybackResumeSegment(totalFrames: 12, progress: .infinity))
    }

    func testRejectsFilesTooLongForSingleAudioPlayerSegment() {
        let tooLong = AVAudioFramePosition(AVAudioFrameCount.max) + 1
        XCTAssertNil(PlaybackResumeSegment(totalFrames: tooLong, progress: 0))
    }
}
