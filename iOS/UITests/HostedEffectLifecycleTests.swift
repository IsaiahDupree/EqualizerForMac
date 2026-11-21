import AudioToolbox
import AVFAudio
import XCTest

final class HostedEffectLifecycleTests: XCTestCase {
    @MainActor
    func testIndependentHostStillRendersEQAfterSonanceTerminates() async throws {
        let sonance = XCUIApplication()
        sonance.launch()

        // The UI test runner is a separate app process hosting the installed Audio Unit.
        let description = AudioComponentDescription(componentType: kAudioUnitType_Effect,
            componentSubType: 0x536E4551, componentManufacturer: 0x49734470,
            componentFlags: 0, componentFlagsMask: 0)
        let effect = try await AVAudioUnit.instantiate(with: description, options: .loadOutOfProcess)
        let parameters = try XCTUnwrap(effect.auAudioUnit.parameterTree)
        let gain = try XCTUnwrap(parameters.allParameters.first { $0.displayName == "Band 6 Gain" })
        gain.value = 6

        let stream = try RenderStream(effect: effect, frequencies: [1_000])
        XCTAssertEqual(try stream.measure()[0], 6, accuracy: 0.25)

        sonance.terminate()
        XCTAssertTrue(sonance.wait(for: .notRunning, timeout: 5))
        XCTAssertEqual(gain.value, 6)
        XCTAssertEqual(try stream.measure()[0], 6, accuracy: 0.25)
    }
}
