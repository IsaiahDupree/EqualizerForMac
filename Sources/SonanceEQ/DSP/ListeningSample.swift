import Foundation

/// A short, synthesized listening sample. Both takes use the same source and have the same RMS.
enum ListeningSample {
    static let sampleRate = 32_000
    static let peakLimit: Float = 0.28

    struct Comparison {
        let original: [Float]
        let tuned: [Float]
    }

    static func render() -> Comparison {
        let notes: [Double] = [130.81, 196, 261.63, 329.63, 196]
        let noteSpacing = 0.35
        let original = (0..<(sampleRate * 2)).map { index -> Float in
            let time = Double(index) / Double(sampleRate)
            var value = 0.0
            for (note, frequency) in notes.enumerated() {
                let elapsed = time - Double(note) * noteSpacing
                guard elapsed >= 0 else { break }
                let phase = 2 * Double.pi * frequency * elapsed
                let envelope = min(elapsed / 0.014, 1) * exp(-5 * elapsed)
                value += envelope * (sin(phase) + 0.35 * sin(phase * 3) + 0.18 * sin(phase * 8))
            }
            let fade = min((2 - time) / 0.05, 1)
            return Float(value * fade)
        }

        var tuned = original
        let engine = EQEngine()
        // The same free Vocal preset and DSP used in the main editor.
        engine.update(bands: Presets.vocal, preampDb: 0, bypassed: false, sampleRate: Double(sampleRate))
        engine.resetState()
        engine.beginRender()
        let count = tuned.count
        tuned.withUnsafeMutableBufferPointer { buffer in
            guard let start = buffer.baseAddress else { return }
            for offset in stride(from: 0, to: count, by: EQEngine.maxFrames) {
                engine.process(channel: 0, data: start.advanced(by: offset),
                               frames: min(EQEngine.maxFrames, count - offset), stride: 1)
            }
        }

        let originalRMS = rms(original)
        let tunedRMS = rms(tuned)
        guard let originalPeak = original.map(abs).max(), originalPeak > 0, originalRMS > 0,
              let tunedPeak = tuned.map(abs).max(), tunedPeak > 0, tunedRMS > 0 else {
            return Comparison(original: original, tuned: tuned)
        }
        let targetRMS = min(0.065, peakLimit * originalRMS / originalPeak, peakLimit * tunedRMS / tunedPeak)
        return Comparison(original: original.map { $0 * (targetRMS / originalRMS) },
                          tuned: tuned.map { $0 * (targetRMS / tunedRMS) })
    }

    static func rms(_ samples: [Float]) -> Float {
        (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }

    static func wave(_ samples: [Float]) -> Data {
        var data = Data(capacity: 44 + samples.count * 2)
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + samples.count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1)) // PCM
        append(UInt16(1)) // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(UInt32(samples.count * 2))
        for sample in samples { append(Int16((sample * Float(Int16.max)).rounded())) }
        return data
    }
}
