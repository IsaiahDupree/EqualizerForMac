import AudioToolbox
import AVFAudio
import XCTest
@testable import SonanceEQiOS

final class AudioUnitIntegrationTests: XCTestCase {
    @MainActor
    func testInstalledEffectProcessesStereoAndBypassesDuringPlayback() async throws {
        let effect = try await installedEffect()
        let tree = try XCTUnwrap(effect.auAudioUnit.parameterTree)
        XCTAssertEqual(tree.allParameters.count, 32)
        let gain = try XCTUnwrap(tree.parameter(withAddress: MobileEQ.address(.gain, band: 5)))
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
        XCTAssertEqual(player.fileName, url.lastPathComponent)
        await player.play()
        XCTAssertEqual(player.state, .playing, player.error ?? "")
        XCTAssertNotNil(player.outputName)
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

private let rate = 48_000.0
private let amplitude = 0.125

private func makeTone(frequencies: [Double], frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: UInt32(frequencies.count)))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    let channels = try XCTUnwrap(buffer.floatChannelData)
    buffer.frameLength = frames
    for (channel, frequency) in frequencies.enumerated() {
        for frame in 0..<Int(frames) {
            channels[channel][frame] = Float(amplitude * sin(2 * .pi * frequency * Double(frame) / rate))
        }
    }
    return buffer
}

private final class RenderStream {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let block: AVAudioPCMBuffer

    init(effect: AVAudioUnit, frequencies: [Double]) throws {
        let input = try makeTone(frequencies: frequencies, frames: 4_800)
        block = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: 960))
        engine.attach(node)
        engine.attach(effect)
        engine.connect(node, to: effect, format: input.format)
        engine.connect(effect, to: engine.mainMixerNode, format: input.format)
        try engine.enableManualRenderingMode(.offline, format: input.format, maximumFrameCount: block.frameCapacity)
        try engine.start()
        node.scheduleBuffer(input, at: nil, options: [.loops])
        node.play()
    }

    deinit {
        node.stop()
        engine.stop()
    }

    func measure() throws -> [Double] {
        for _ in 0..<24 {
            let result = try engine.renderOffline(block.frameCapacity, to: block)
            XCTAssertEqual(result, .success)
            XCTAssertEqual(block.frameLength, block.frameCapacity)
        }
        let samples = try XCTUnwrap(block.floatChannelData)
        return (0..<Int(block.format.channelCount)).map { channel in
            let power = (0..<Int(block.frameLength)).reduce(0.0) { sum, frame in
                let sample = Double(samples[channel][frame])
                return sum + sample * sample
            } / Double(block.frameLength)
            return 10 * log10(power / (amplitude * amplitude / 2))
        }
    }
}
