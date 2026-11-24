import XCTest
@testable import SonanceEQiOS

final class PlaybackRouteFormatTests: XCTestCase {
    func testSummaryUsesObservedRouteValues() {
        let format = PlaybackRouteFormat(sampleRateHz: 48_000, outputChannels: 2,
                                         ioBufferDurationSeconds: 0.005333)
        XCTAssertEqual(format.summary, "48000 Hz · 2 ch · 5.3 ms I/O buffer")
    }

    func testUnavailableOrInvalidRouteValuesStayUnknown() {
        let format = PlaybackRouteFormat(sampleRateHz: 0, outputChannels: 2,
                                         ioBufferDurationSeconds: .infinity)
        XCTAssertNil(format.sampleRateHz)
        XCTAssertNil(format.ioBufferDurationSeconds)
        XCTAssertNil(format.summary)
    }
}
