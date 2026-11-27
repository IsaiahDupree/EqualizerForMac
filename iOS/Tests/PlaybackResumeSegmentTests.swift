import AVFAudio
import XCTest
@testable import SonanceEQiOS

final class PlaybackResumeSegmentTests: XCTestCase {
    func testStartsAtBeginningWhenPlaybackIsFresh() {
        let segment = PlaybackResumeSegment(totalFrames: 48_000, progress: 0)
        XCTAssertEqual(segment?.startingFrame, 0)
        XCTAssertEqual(segment?.frameCount, 48_000)
    }

    func testUsesSavedFractionOfFileForResume() {
        let segment = PlaybackResumeSegment(totalFrames: 96_000, progress: 0.375)
        XCTAssertEqual(segment?.startingFrame, 36_000)
        XCTAssertEqual(segment?.frameCount, 60_000)
        XCTAssertEqual(segment?.progress(renderedFrames: 12_000, totalFrames: 96_000) ?? 0,
                       0.5, accuracy: 0.000_001)
    }

    func testClampsProgressToValidFileRange() {
        let segment = PlaybackResumeSegment(totalFrames: 12, progress: -1)
        XCTAssertEqual(segment?.startingFrame, 0)
        XCTAssertEqual(segment?.frameCount, 12)
        XCTAssertNil(PlaybackResumeSegment(totalFrames: 12, progress: 1))
        XCTAssertNil(PlaybackResumeSegment(totalFrames: 12, progress: .infinity))
    }

    func testRejectsFilesTooLongForSingleAudioPlayerSegment() {
        let tooLong = AVAudioFramePosition(AVAudioFrameCount.max) + 1
        XCTAssertNil(PlaybackResumeSegment(totalFrames: tooLong, progress: 0))
    }

    func testCarPlayAndBluetoothReconnectResumeOnlyForSameNonemptyOutputID() {
        XCTAssertTrue(PlaybackRouteReconnectPolicy.isReconnectable(portType: .carAudio))
        XCTAssertTrue(PlaybackRouteReconnectPolicy.isReconnectable(portType: .bluetoothA2DP))
        XCTAssertFalse(PlaybackRouteReconnectPolicy.isReconnectable(portType: .builtInSpeaker))
        XCTAssertTrue(PlaybackRouteReconnectPolicy.shouldResume(expectedOutputID: "carplay-route-1",
                                                                 currentOutputID: "carplay-route-1"))
        XCTAssertTrue(PlaybackRouteReconnectPolicy.shouldResume(expectedOutputID: "bluetooth-1",
                                                                 currentOutputID: "bluetooth-1"))
        XCTAssertFalse(PlaybackRouteReconnectPolicy.shouldResume(expectedOutputID: "carplay-route-1",
                                                                  currentOutputID: "device-2"))
        XCTAssertFalse(PlaybackRouteReconnectPolicy.shouldResume(expectedOutputID: nil,
                                                                  currentOutputID: "device-1"))
        XCTAssertFalse(PlaybackRouteReconnectPolicy.shouldResume(expectedOutputID: "",
                                                                  currentOutputID: ""))
    }

    func testEngineConfigurationChangePreservesReconnectTarget() {
        XCTAssertEqual(
            PlaybackRouteReconnectPolicy.configurationChangeReconnectID(
                pendingOutputID: nil,
                activeOutputID: "bluetooth-1"),
            "bluetooth-1")
        XCTAssertEqual(
            PlaybackRouteReconnectPolicy.configurationChangeReconnectID(
                pendingOutputID: "carplay-1",
                activeOutputID: "bluetooth-1"),
            "carplay-1")
        XCTAssertNil(PlaybackRouteReconnectPolicy.configurationChangeReconnectID(
            pendingOutputID: "",
            activeOutputID: nil))
    }
}
