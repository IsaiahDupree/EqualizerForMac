import AVFAudio
import Foundation

#if SONANCE_STANDALONE_RENDER_PROOF
let kSubsystem = "com.isaiahdupree.SonanceEQ.RenderProof"
#else
import Testing
@testable import SonanceEQ
#endif

/// Real PCM buffers, the shipping DSP, and the shipping heartbeat. Malformed buffer metadata is
/// an explicit boundary input, never a replacement audio provider or a physical-device claim.
enum AudioBufferRouterProof {
    static let cases = [
        "mono", "interleaved", "planar", "eight_interleaved", "eight_planar", "silence",
        "mid_interleaved", "mid_planar", "large_mid_interleaved", "large_mid_planar",
        "large_fir_interleaved", "large_fir_planar", "large_fir_mid_interleaved", "large_fir_mid_planar",
        "empty", "missing_input", "missing_output",
        "unequal_planar", "short_input", "wrong_channels", "zero_channels", "partial_frame",
        "unaligned_pointer", "no_output", "extra_input", "too_many_channels",
    ]

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
    }

    static func run(_ name: String) throws {
        let planar = name.contains("planar") || name == "extra_input"
        let channels: AVAudioChannelCount = name == "mono" ? 1 : (name.contains("eight") ? 8 : 2)
        let count = name.hasPrefix("large") ? EQEngine.maxFrames + 257 : 256
        guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels)
        else { throw Failure(description: "PCM channel layout unavailable") }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                   interleaved: !planar, channelLayout: layout)
        guard let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))
        else { throw Failure(description: "PCM allocation unavailable") }
        input.frameLength = AVAudioFrameCount(count)
        output.frameLength = AVAudioFrameCount(count)
        let inputList = input.mutableAudioBufferList
        let outputList = output.mutableAudioBufferList
        let inputs = UnsafeMutableAudioBufferListPointer(inputList)
        let outputs = UnsafeMutableAudioBufferListPointer(outputList)
        // AVAudioPCMBuffer owns the actual allocations; restore metadata before its destruction.
        let originalInputs = Array(inputs), originalOutputs = Array(outputs)
        let originalInputCount = inputList.pointee.mNumberBuffers
        let originalOutputCount = outputList.pointee.mNumberBuffers
        defer {
            inputList.pointee.mNumberBuffers = originalInputCount
            outputList.pointee.mNumberBuffers = originalOutputCount
            for index in originalInputs.indices { inputs[index] = originalInputs[index] }
            for index in originalOutputs.indices { outputs[index] = originalOutputs[index] }
        }
        for (bufferIndex, buffer) in inputs.enumerated() {
            let samples = buffer.mData!.assumingMemoryBound(to: Float.self)
            for index in 0..<(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size) {
                // A computed test tone, not captured/private audio.
                let frame = index / Int(buffer.mNumberChannels)
                let channel = planar ? bufferIndex : index % Int(buffer.mNumberChannels)
                samples[index] = name == "silence" ? 0
                    : Float(sin(2 * .pi * 1000 * Double(frame) / 48_000 + Double(channel) * 0.17)) * 0.25
            }
        }
        for buffer in outputs { memset(buffer.mData!, 0x55, Int(buffer.mDataByteSize)) }
        let inputBefore = originalInputs.map { Data(bytes: $0.mData!, count: Int($0.mDataByteSize)) }
        let outputBefore = originalOutputs.map { Data(bytes: $0.mData!, count: Int($0.mDataByteSize)) }

        let eq = EQEngine()
        let midSide = name.contains("mid") || name == "unequal_planar"
        let linear = name.contains("fir")
        eq.update(bands: [], sideBands: [], preampDb: midSide || linear ? -6 : 0,
                  bypassed: false, sampleRate: 48_000, linearPhase: linear, midSide: midSide)
        eq.resetState()
        let watchdog = AudioRouteWatchdog()
        let heartbeat = watchdog.beginRoute()
        var valid = false
        switch name {
        case "empty":
            for index in inputs.indices { inputs[index].mDataByteSize = 0; outputs[index].mDataByteSize = 0 }
        case "missing_input": inputs[0].mData = nil
        case "missing_output": outputs[0].mData = nil
        case "unequal_planar":
            inputs[1].mDataByteSize = 8
            outputs[1].mDataByteSize = 8
        case "short_input": inputs[0].mDataByteSize /= 2
        case "wrong_channels": inputs[0].mNumberChannels = 1
        case "zero_channels": inputs[0].mNumberChannels = 0; outputs[0].mNumberChannels = 0
        case "partial_frame": inputs[0].mDataByteSize -= 1; outputs[0].mDataByteSize -= 1
        case "unaligned_pointer":
            inputs[0].mData = inputs[0].mData!.advanced(by: 1)
            outputs[0].mData = outputs[0].mData!.advanced(by: 1)
            inputs[0].mDataByteSize -= 8; outputs[0].mDataByteSize -= 8
        case "no_output": outputList.pointee.mNumberBuffers = 0
        case "extra_input": outputList.pointee.mNumberBuffers = 1
        case "too_many_channels":
            inputs[0].mNumberChannels = 16; outputs[0].mNumberChannels = 16
        default: valid = true
        }

        let result = AudioBufferRouter.render(eq, input: UnsafePointer(inputList),
                                               output: outputList, heartbeat: heartbeat)
        try require(result == valid, "\(name): admission mismatch")
        try require(heartbeat.deliveredBlocks == (valid ? 1 : 0), "\(name): false/missing route heartbeat")
        for index in originalInputs.indices {
            try require(Data(bytes: originalInputs[index].mData!, count: Int(originalInputs[index].mDataByteSize))
                        == inputBefore[index], "\(name): input was modified")
        }
        if valid {
            let gain = midSide || linear ? pow(10.0, -6.0 / 20) : 1
            // FIR's centered delta has a known sample delay. Verify beyond its startup region and
            // across the 8192-frame boundary, so an oversized unprocessed block cannot pass.
            // The existing processor correlates a flat-design impulse centered at L/2 against
            // L-1 preceding samples: its observable delay is L-1-L/2, i.e. 1023 samples.
            let delay = linear ? FIRProcessor.length - 1 - FIRProcessor.length / 2 : 0
            for index in outputs.indices {
                let source = inputs[index].mData!.assumingMemoryBound(to: Float.self)
                let destination = outputs[index].mData!.assumingMemoryBound(to: Float.self)
                let stride = Int(outputs[index].mNumberChannels)
                for frame in delay..<count {
                    for channel in 0..<stride {
                        let expected = source[(frame - delay) * stride + channel] * Float(gain)
                        try require(abs(destination[frame * stride + channel] - expected) < 0.0001,
                                    "\(name): DSP/copy mismatch at frame \(frame)")
                    }
                }
            }
        } else {
            let currentOutputs = UnsafeMutableAudioBufferListPointer(outputList)
            for index in originalOutputs.indices {
                let original = originalOutputs[index]
                let bytes = original.mData!.assumingMemoryBound(to: UInt8.self)
                let current = index < currentOutputs.count ? currentOutputs[index] : nil
                for byte in 0..<Int(original.mDataByteSize) {
                    let address = Int(bitPattern: original.mData!) + byte
                    let start = current?.mData.map { Int(bitPattern: $0) }
                    let cleared = start.map { address >= $0 && address < $0 + Int(current!.mDataByteSize) } ?? false
                    try require(bytes[byte] == (cleared ? 0 : outputBefore[index][byte]),
                                "\(name): silence/guard mismatch at buffer \(index), byte \(byte)")
                }
            }
        }
    }
}

#if SONANCE_STANDALONE_RENDER_PROOF
@main enum RenderProof {
    static func main() {
        setbuf(stdout, nil)
        do {
            for name in AudioBufferRouterProof.cases {
                try AudioBufferRouterProof.run(name)
                print("PASS \(name)")
            }
            print("PASS \(AudioBufferRouterProof.cases.count) render cases; physical audibility not tested")
        } catch {
            print("FAIL \(error)")
            exit(1)
        }
    }
}
#else
@Suite(.serialized) struct AudioBufferRouterTests {
    @Test(arguments: AudioBufferRouterProof.cases)
    func shippingRenderBuffers(_ name: String) throws { try AudioBufferRouterProof.run(name) }
}
#endif
