import AudioToolbox
import Foundation

/// The Float32 buffer path used by the global tap's IOProc. Validation precedes all DSP reads:
/// an empty/malformed callback silences its writable output and cannot establish route health.
/// Valid silence does establish buffer delivery; this is never proof of audible output.
enum AudioBufferRouter {
    @discardableResult
    static func render(_ eq: EQEngine, input: UnsafePointer<AudioBufferList>,
                       output: UnsafeMutablePointer<AudioBufferList>,
                       heartbeat: AudioRouteWatchdog.Heartbeat) -> Bool {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        guard let frames = validatedFrames(inputs, outputs) else {
            for buffer in outputs {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            return false
        }

        eq.beginRender()
        for index in outputs.indices {
            // Both pointers and matching full-frame byte counts were checked together.
            memmove(outputs[index].mData!, inputs[index].mData!, Int(outputs[index].mDataByteSize))
        }

        // Large valid callbacks are split at the DSP scratch capacity; neither FIR nor Mid-Side
        // may silently skip processing and still report a successful route.
        var offset = 0
        while offset < frames {
            let count = min(EQEngine.maxFrames, frames - offset)
            if eq.isMidSide, outputs.count == 1, outputs[0].mNumberChannels == 2 {
                let samples = outputs[0].mData!.assumingMemoryBound(to: Float.self) + offset * 2
                eq.processMidSide(left: samples, right: samples + 1, frames: count, strideL: 2, strideR: 2)
            } else if eq.isMidSide, outputs.count == 2,
                      outputs[0].mNumberChannels == 1, outputs[1].mNumberChannels == 1 {
                eq.processMidSide(left: outputs[0].mData!.assumingMemoryBound(to: Float.self) + offset,
                                  right: outputs[1].mData!.assumingMemoryBound(to: Float.self) + offset,
                                  frames: count, strideL: 1, strideR: 1)
            } else {
                var channelOffset = 0
                for buffer in outputs {
                    let channels = Int(buffer.mNumberChannels)
                    let samples = buffer.mData!.assumingMemoryBound(to: Float.self) + offset * channels
                    for channel in 0..<channels {
                        eq.process(channel: channelOffset + channel, data: samples + channel,
                                   frames: count, stride: channels)
                    }
                    channelOffset += channels
                }
            }
            offset += count
        }
        heartbeat.recordRender()
        return true
    }

    private static func validatedFrames(_ inputs: UnsafeMutableAudioBufferListPointer,
                                        _ outputs: UnsafeMutableAudioBufferListPointer) -> Int? {
        guard !outputs.isEmpty, inputs.count == outputs.count else { return nil }
        var frames: Int?
        var channelCount = 0
        for index in outputs.indices {
            let source = inputs[index], destination = outputs[index]
            let channels = Int(destination.mNumberChannels)
            guard channels > 0, source.mNumberChannels == destination.mNumberChannels,
                  let sourceData = source.mData, let destinationData = destination.mData,
                  Int(bitPattern: sourceData) % MemoryLayout<Float>.alignment == 0,
                  Int(bitPattern: destinationData) % MemoryLayout<Float>.alignment == 0,
                  source.mDataByteSize == destination.mDataByteSize else { return nil }
            let bytesPerFrame = MemoryLayout<Float>.size * channels
            let bytes = Int(destination.mDataByteSize)
            guard bytes > 0, bytes % bytesPerFrame == 0 else { return nil }
            let count = bytes / bytesPerFrame
            guard frames == nil || frames == count else { return nil }
            frames = count
            channelCount += channels
            guard channelCount <= EQEngine.maxChannels else { return nil }
        }
        return frames
    }
}
