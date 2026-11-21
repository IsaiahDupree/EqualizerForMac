import AVFAudio
import XCTest

private let rate = 48_000.0
private let amplitude = 0.125

func makeTone(frequencies: [Double], frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
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

final class RenderStream {
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
