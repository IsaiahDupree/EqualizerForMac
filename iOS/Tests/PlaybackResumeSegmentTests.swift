import AVFAudio
import XCTest
@testable import SonanceEQiOS

final class PlaybackResumeSegmentTests: XCTestCase {
    func testStartsAtBeginningWhenPlaybackIsFresh() {
        XCTAssertEqual(PlaybackResumeSegment(totalFrames: 48_000, progress: 0),
                       PlaybackResumeSegment(startingFrame: 0, frameCount: 48_000))
    }

    func testUsesSavedFractionOfFileForResume() {
        XCTAssertEqual(PlaybackResumeSegment(totalFrames: 96_000, progress: 0.375),
                       PlaybackResumeSegment(startingFrame: 36_000, frameCount: 60_000))
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
