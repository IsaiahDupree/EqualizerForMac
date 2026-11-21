import AudioToolbox
import AVFAudio
import AVFoundation
import CoreAudioKit
import XCTest
@testable import SonanceEQiOS

final class AudioUnitIntegrationTests: XCTestCase {
    @MainActor
    func testInstalledEffectProcessesStereoAndBypassesDuringPlayback() async throws {
        let effect = try await installedEffect()
        let tree = try XCTUnwrap(effect.auAudioUnit.parameterTree)
        XCTAssertEqual(tree.allParameters.count, 62)
        let gain = try XCTUnwrap(tree.parameter(withAddress: MobileEQ.address(.gain, band: 5)))
        XCTAssertEqual(gain.address, 18, "Existing host sessions use the original parameter addresses")
        let preamp = try XCTUnwrap(tree.parameter(withAddress: MobileEQ.preampAddress))
        gain.value = 9
        preamp.value = -3

        let stream = try RenderStream(effect: effect, frequencies: [1_000, 6_000])
        let wet = try stream.measure()
        XCTAssertEqual(wet[0], 6, accuracy: 0.25)
        XCTAssertEqual(wet[1], -2.9, accuracy: 0.35)

        effect.auAudioUnit.shouldBypassEffect = true
        let dry = try stream.measure()
        XCTAssertEqual(dry[0], 0, accuracy: 0.08)
        XCTAssertEqual(dry[1], 0, accuracy: 0.08)

        effect.auAudioUnit.shouldBypassEffect = false
        gain.value = -6
        let cut = try stream.measure()
        XCTAssertEqual(cut[0], -9, accuracy: 0.25)
    }

    @MainActor
    func testHostRestoresParameterStateAndRendersMono() async throws {
        let first = try await installedEffect()
        let tree = try XCTUnwrap(first.auAudioUnit.parameterTree)
        let center = MobileEQ.address(.frequency, band: 0)
        let gain = MobileEQ.address(.gain, band: 0)
        try XCTUnwrap(tree.parameter(withAddress: center)).value = 750
        try XCTUnwrap(tree.parameter(withAddress: gain)).value = 6

        let restored = try await installedEffect()
        restored.auAudioUnit.fullState = try XCTUnwrap(first.auAudioUnit.fullState)
        let restoredTree = try XCTUnwrap(restored.auAudioUnit.parameterTree)
        XCTAssertEqual(try XCTUnwrap(restoredTree.parameter(withAddress: center)).value, 750)
        XCTAssertEqual(try XCTUnwrap(restoredTree.parameter(withAddress: gain)).value, 6)
        let stream = try RenderStream(effect: restored, frequencies: [750])
        XCTAssertEqual(try stream.measure()[0], 6, accuracy: 0.25)
    }

    @MainActor
    func testMacFilterShapesRenderAndRestoreInAHost() async throws {
        let effect = try await installedEffect()
        let tree = try XCTUnwrap(effect.auAudioUnit.parameterTree)
        func parameter(_ control: MobileEQ.Control) throws -> AUParameter {
            try XCTUnwrap(tree.parameter(withAddress: MobileEQ.address(control, band: 0)))
        }
        try parameter(.type).value = Float(try XCTUnwrap(MobileEQ.filterTypes.firstIndex(of: .lowShelf)))
        try parameter(.frequency).value = 400
        try parameter(.gain).value = 8
        try parameter(.quality).value = 0.707
        let restored = try await installedEffect()
        restored.auAudioUnit.fullState = try XCTUnwrap(effect.auAudioUnit.fullState)
        let spectrum = try RenderStream(effect: restored, frequencies: [100, 3_000]).measure()
        XCTAssertEqual(spectrum[0], 8, accuracy: 0.3)
        XCTAssertEqual(spectrum[1], 0, accuracy: 0.15)

        let cut = try await installedEffect()
        let cutTree = try XCTUnwrap(cut.auAudioUnit.parameterTree)
        try XCTUnwrap(cutTree.parameter(withAddress: MobileEQ.address(.type, band: 0))).value =
            Float(try XCTUnwrap(MobileEQ.filterTypes.firstIndex(of: .highPass)))
        try XCTUnwrap(cutTree.parameter(withAddress: MobileEQ.address(.slope, band: 0))).value =
            Float(try XCTUnwrap(FilterDesigner.slopes.firstIndex(of: 24)))
        try XCTUnwrap(cutTree.parameter(withAddress: MobileEQ.address(.frequency, band: 0))).value = 400
        let response = try RenderStream(effect: cut, frequencies: [200, 3_000]).measure()
        XCTAssertEqual(response[0], -24, accuracy: 1)
        XCTAssertEqual(response[1], 0, accuracy: 0.12)
    }

    @MainActor
    func testHostCanRequestSonanceEditor() async throws {
        let effect = try await installedEffect()
        XCTAssertTrue(effect.auAudioUnit.providesUserInterface)
        let editor = await effect.auAudioUnit.requestViewController()
        XCTAssertNotNil(editor)
    }

    @MainActor
    func testFloatingCurveVideoRendersTheFilterAndPlaybackProgress() throws {
        let renderer = CurveVideoRenderer()
        var settings = MobileEQSettings()
        func render(progress: Double) throws -> Data {
            let frame = CurveVideoFrame(title: "Sonance", settings: settings, sampleRate: 48_000, progress: progress)
            let sample = try XCTUnwrap(renderer.render(frame))
            XCTAssertTrue(CMSampleBufferDataIsReady(sample))
            let image = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            XCTAssertEqual(CVPixelBufferGetWidth(image), 480)
            XCTAssertEqual(CVPixelBufferGetHeight(image), 270)
            CVPixelBufferLockBaseAddress(image, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
            let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(image))
            return Data(bytes: address, count: CVPixelBufferGetBytesPerRow(image) * CVPixelBufferGetHeight(image))
        }
        let flat = try render(progress: 0)
        settings.bands[5].gain = 10
        let boosted = try render(progress: 0)
        XCTAssertNotEqual(flat, boosted)
        XCTAssertNotEqual(boosted, try render(progress: 0.5))
    }

    @MainActor
    func testAppPlaysASelectedAudioFileThroughItsEmbeddedEffect() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let buffer = try makeTone(frequencies: [1_000], frames: 144_000)
        do {
            let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
            try file.write(from: buffer)
        }

        let player = PreviewPlayer()
        defer { player.stop() }
        player.select(url)
        var boosted = MobileEQSettings()
        boosted.bands[5].gain = 6
        player.apply(boosted)
        XCTAssertEqual(player.fileName, url.lastPathComponent)
        await player.play()
        XCTAssertEqual(player.state, .playing, player.error ?? "")
        XCTAssertNotNil(player.outputName)
        var measured: AudioAnalysisFrame?
        for _ in 0..<22 {
            if let frame = player.readAnalysis(), frame.dominantFrequency != nil {
                measured = frame
                break
            }
            try await Task.sleep(for: .milliseconds(70))
        }
        let frame = try XCTUnwrap(measured, "The visualizer should receive actual audio from the EQ output")
        XCTAssertEqual(try XCTUnwrap(frame.dominantFrequency), 1_000, accuracy: 25)
        XCTAssertEqual(frame.left.peak, -12.1, accuracy: 0.6)
        XCTAssertNil(frame.right)
        player.pause()
        XCTAssertEqual(player.state, .paused)
        await player.play()
        XCTAssertEqual(player.state, .playing, player.error ?? "")
        player.stop()
        XCTAssertEqual(player.state, .idle)
        XCTAssertNil(player.outputName)
    }

    private func installedEffect() async throws -> AVAudioUnit {
        let components = AVAudioUnitComponentManager.shared().components(matching: MobileEQ.component)
        XCTAssertEqual(components.count, 1, "The embedded AUv3 must be visible to hosts")
        return try await AVAudioUnit.instantiate(with: MobileEQ.component, options: .loadOutOfProcess)
    }
}
