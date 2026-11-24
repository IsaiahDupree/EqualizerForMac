import AudioToolbox
import AVFAudio
import Foundation

/// Test-only input whose expected samples are independent of Sonance's DSP.
/// The integer-frequency, one-second signals join continuously when repeated.
struct QualitySignal {
    let sampleRate: Double
    let channels: [[Float]]

    static func multitone(sampleRate: Double, channels count: Int) -> QualitySignal {
        let frequencies = [[137.0, 997.0, 3_001.0], [239.0, 1_499.0, 5_003.0]]
        let samples = (0..<count).map { channel in
            (0..<Int(sampleRate)).map { frame -> Float in
                let time = Double(frame) / sampleRate
                return Float(frequencies[channel].reduce(0.0) {
                    $0 + (0.125 / 3) * sin(2 * .pi * $1 * time)
                })
            }
        }
        return QualitySignal(sampleRate: sampleRate, channels: samples)
    }

    /// A nil frequency deliberately supplies a silent channel for isolation tests.
    static func tones(sampleRate: Double, frequencies: [Double?], amplitude: Double = 0.125) -> QualitySignal {
        QualitySignal(sampleRate: sampleRate, channels: frequencies.map { frequency in
            (0..<Int(sampleRate)).map { frame in
                frequency.map { Float(amplitude * sin(2 * .pi * $0 * Double(frame) / sampleRate)) } ?? 0
            }
        })
    }

    func expected(frames: Int, offset: Int = 0, gain: Double = 1) -> [[Float]] {
        channels.map { channel in
            (0..<frames).map { Float(Double(channel[(offset + $0) % channel.count]) * gain) }
        }
    }
}

/// Sample comparison deliberately does not align, normalize, or discard output.
/// Such operations could hide a lost block, a gain error, or a channel swap.
struct QualityComparison {
    let shapeMatches: Bool
    let nonFiniteSamples: Int
    let maximumError: Double
    let rmsError: Double

    init(actual: [[Float]], expected: [[Float]]) {
        shapeMatches = actual.count == expected.count &&
            zip(actual, expected).allSatisfy { pair in pair.0.count == pair.1.count }
        var invalid = 0
        var maximum = 0.0
        var energy = 0.0
        var count = 0
        for (observed, reference) in zip(actual, expected) {
            for (sample, target) in zip(observed, reference) {
                guard sample.isFinite, target.isFinite else {
                    invalid += 1
                    continue
                }
                let error = Double(sample) - Double(target)
                maximum = max(maximum, abs(error))
                energy += error * error
                count += 1
            }
        }
        nonFiniteSamples = invalid
        maximumError = maximum
        rmsError = count > 0 ? sqrt(energy / Double(count)) : .infinity
    }

    /// Proposed project tolerances for a unity/reference comparison, not an
    /// acoustic fidelity specification or an Apple/Bluetooth standard.
    var passesUnityTolerance: Bool {
        shapeMatches && nonFiniteSamples == 0 && maximumError <= 1e-4 && rmsError <= 1e-5
    }

    var description: String {
        "shape=\(shapeMatches), nonfinite=\(nonFiniteSamples), maxError=\(maximumError), rmsError=\(rmsError)"
    }
}

struct QualityCapture {
    let samples: [[Float]]
    let sampleRate: Double
    let offlineContextRetries: Int

    var nonFiniteSamples: Int { samples.reduce(0) { $0 + $1.filter { !$0.isFinite }.count } }
    var peak: Double { samples.flatMap { $0 }.reduce(0) { max($0, abs(Double($1))) } }

    func rms(channel: Int, dropping frames: Int = 0) -> Double {
        let values = samples[channel].dropFirst(frames)
        guard !values.isEmpty else { return .nan }
        return sqrt(values.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(values.count))
    }

    /// Specialized to the continuous 1 kHz / 3 kHz fixtures in this suite,
    /// whose lowest expected RMS is above 0.01. A 2 ms window covers complete
    /// tone cycles at 48 kHz, so normal zero crossings do not trigger it.
    /// Windows overlap at 0.5 ms hops: 5 ms and 10 ms total mutes cannot hide
    /// across the old disjoint 10 ms boundaries. Fault-injection tests exercise
    /// this exact method, including those boundary-crossing cases.
    ///
    /// Returns affected WINDOW count, not distinct dropout count. It does not
    /// detect every sub-window glitch, click, partial dip, or acoustic failure.
    /// Do not apply it to arbitrary music, intentional cuts, or low-level input.
    /// Nonfinite samples and timeline/frame defects are checked separately.
    func knownToneGapWindowCount(channel: Int, dropping frames: Int = 0) -> Int {
        let values = samples[channel]
        let framesPerWindow = max(1, Int((sampleRate * 0.002).rounded()))
        let hopFrames = max(1, Int((sampleRate * 0.0005).rounded()))
        let threshold = 0.002
        guard frames >= 0, frames < values.count else { return 0 }
        var quiet = 0
        var start = frames
        while start + framesPerWindow <= values.count {
            let energy = values[start..<(start + framesPerWindow)].reduce(0.0) {
                $0 + Double($1) * Double($1)
            }
            if sqrt(energy / Double(framesPerWindow)) < threshold { quiet += 1 }
            start += hopFrames
        }
        return quiet
    }
}

private enum QualityRenderError: Error, CustomStringConvertible {
    case failure(String)
    var description: String {
        switch self { case .failure(let message): return message }
    }
}

/// Mutable only on the engine's serialized source-render path. It owns immutable
/// test samples; the callback does no allocation, file I/O, logging, or locking.
private final class QualitySourceCursor {
    let signal: QualitySignal
    var position = 0
    init(_ signal: QualitySignal) { self.signal = signal }

    func fill(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard buffers.count == signal.channels.count else { return kAudioUnitErr_FormatNotSupported }
        for channel in signal.channels.indices {
            guard buffers[channel].mNumberChannels == 1,
                  Int(buffers[channel].mDataByteSize) >= frames * MemoryLayout<Float>.size,
                  let data = buffers[channel].mData else { return kAudioUnitErr_FormatNotSupported }
            let destination = data.assumingMemoryBound(to: Float.self)
            let source = signal.channels[channel]
            for frame in 0..<frames { destination[frame] = source[(position + frame) % source.count] }
        }
        position += frames
        return noErr
    }
}

/// Captures the actual installed AU through AVAudioEngine. This is an OFFLINE
/// host test: it cannot prove callback deadlines, Bluetooth RF reliability, or
/// playback while a physical iPhone is locked. Every successful output block is
/// retained, including startup. No silent blocks are skipped to make a test pass.
final class QualityRenderStream {
    private let engine = AVAudioEngine()
    private let source: AVAudioSourceNode
    private let effect: AVAudioUnit
    private let output: AVAudioPCMBuffer
    private let signal: QualitySignal
    private let maximumFrames: AVAudioFrameCount
    private var closed = false

    init(effect: AVAudioUnit, signal: QualitySignal, maximumFrames: AVAudioFrameCount = 2_048) throws {
        guard !signal.channels.isEmpty, signal.channels.allSatisfy({ !$0.isEmpty }),
              maximumFrames > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: signal.sampleRate,
                                         channels: AVAudioChannelCount(signal.channels.count)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFrames) else {
            throw QualityRenderError.failure("Invalid deterministic test signal/format")
        }
        self.effect = effect
        self.signal = signal
        self.output = buffer
        self.maximumFrames = maximumFrames
        let cursor = QualitySourceCursor(signal)
        source = AVAudioSourceNode(format: format) { isSilence, _, frames, list in
            isSilence.pointee = false
            return cursor.fill(list, frames: Int(frames))
        }
        engine.attach(source)
        engine.attach(effect)
        engine.connect(source, to: effect, format: format)
        engine.connect(effect, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maximumFrames)
            try engine.start()
        } catch {
            close()
            throw error
        }
    }

    deinit { close() }

    func close() {
        guard !closed else { return }
        closed = true
        engine.stop()
        engine.disableManualRenderingMode()
        engine.disconnectNodeOutput(source)
        engine.disconnectNodeOutput(effect)
        engine.detach(effect)
        engine.detach(source)
    }

    func capture(frames: Int, blockPattern: [AVAudioFrameCount]) throws -> QualityCapture {
        guard !closed, frames > 0, !blockPattern.isEmpty,
              blockPattern.allSatisfy({ $0 > 0 && $0 <= maximumFrames }) else {
            throw QualityRenderError.failure("Render request exceeds the negotiated test maximum")
        }
        var samples = signal.channels.map { _ -> [Float] in
            var channel: [Float] = []
            channel.reserveCapacity(frames)
            return channel
        }
        var rendered = 0
        var blockIndex = 0
        var contextRetries = 0
        while rendered < frames {
            let requested = min(blockPattern[blockIndex % blockPattern.count], AVAudioFrameCount(frames - rendered))
            let before = engine.manualRenderingSampleTime
            var attempts = 0
            while true {
                output.frameLength = 0
                let result = try engine.renderOffline(requested, to: output)
                if result == .success { break }
                // AVAudioEngine permits retrying this offline status. It must
                // not advance the timeline or consume a nominal output block.
                // These retries are reported, not called Bluetooth underruns.
                guard result == .cannotDoInCurrentContext,
                      engine.manualRenderingSampleTime == before, attempts < 100 else {
                    throw QualityRenderError.failure("Offline render failed at frame \(rendered): \(result)")
                }
                attempts += 1
                contextRetries += 1
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard output.frameLength == requested,
                  engine.manualRenderingSampleTime == before + AVAudioFramePosition(requested),
                  let channels = output.floatChannelData else {
                throw QualityRenderError.failure("Incomplete or discontinuous output at frame \(rendered)")
            }
            for channel in samples.indices {
                samples[channel].append(contentsOf: UnsafeBufferPointer(start: channels[channel], count: Int(requested)))
            }
            rendered += Int(requested)
            blockIndex += 1
        }
        return QualityCapture(samples: samples, sampleRate: signal.sampleRate, offlineContextRetries: contextRetries)
    }
}
