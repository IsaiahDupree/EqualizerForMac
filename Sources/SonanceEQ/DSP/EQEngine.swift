import Foundation
import os

/// Real-time EQ processor: a cascade of biquads applied per channel.
///
/// Design notes:
/// - Control plane (UI thread) calls `update(...)`, which computes coefficients
///   and stores them behind a lock.
/// - Audio plane (IOProc thread) calls `beginRender()` once per render cycle to
///   snapshot the latest coefficients into preallocated C buffers, then
///   `process(channel:...)` per channel. No allocations or Swift-array growth
///   happen on the audio thread.
///
/// M0/M1: a small unfair-lock critical section in `beginRender()` is acceptable.
/// M2 will replace it with a fully lock-free double-buffered swap and ramped
/// (`vDSP_biquadm_SetTargets`) coefficient updates to kill zipper noise.
final class EQEngine {
    static let maxChannels = 8
    static let maxBands = 32

    private struct Control {
        var coeffs: [BiquadCoeffs] = []
        var preamp: Float = 1
        var bypassed: Bool = false
    }

    private let control = OSAllocatedUnfairLock(initialState: Control())

    // Audio-thread-owned snapshot (written only in beginRender, read in process).
    private let coeffBuf: UnsafeMutablePointer<BiquadCoeffs>
    private let z1: UnsafeMutablePointer<Float>   // [channel * maxBands + band]
    private let z2: UnsafeMutablePointer<Float>
    private var activeCount = 0
    private var renderPreamp: Float = 1
    private var renderBypass = false

    private let log = Logger(subsystem: kSubsystem, category: "EQEngine")

    init() {
        coeffBuf = .allocate(capacity: Self.maxBands)
        coeffBuf.initialize(repeating: .identity, count: Self.maxBands)
        let stateCount = Self.maxChannels * Self.maxBands
        z1 = .allocate(capacity: stateCount)
        z2 = .allocate(capacity: stateCount)
        z1.initialize(repeating: 0, count: stateCount)
        z2.initialize(repeating: 0, count: stateCount)
    }

    deinit {
        coeffBuf.deallocate()
        z1.deallocate()
        z2.deallocate()
    }

    /// Reset filter memory (call when the stream restarts to avoid stale transients).
    func resetState() {
        let n = Self.maxChannels * Self.maxBands
        z1.update(repeating: 0, count: n)
        z2.update(repeating: 0, count: n)
    }

    // MARK: Control plane (UI thread)

    func update(bands: [EQBand], preampDb: Float, bypassed: Bool, sampleRate: Double) {
        var coeffs: [BiquadCoeffs] = []
        coeffs.reserveCapacity(bands.count)
        for band in bands where band.enabled {
            coeffs.append(RBJ.coeffs(type: band.type,
                                     sampleRate: sampleRate,
                                     freq: band.frequency,
                                     gainDb: Double(band.gain),
                                     q: band.q))
            if coeffs.count >= Self.maxBands { break }
        }
        let snapshot = coeffs
        let preamp = Float(pow(10, preampDb / 20))
        control.withLock { c in
            c.coeffs = snapshot
            c.preamp = preamp
            c.bypassed = bypassed
        }
    }

    // MARK: Audio plane (IOProc thread)

    /// Snapshot the latest control state. Call once per render cycle before `process`.
    func beginRender() {
        control.withLock { c in
            let n = min(c.coeffs.count, Self.maxBands)
            for i in 0..<n { coeffBuf[i] = c.coeffs[i] }
            activeCount = n
            renderPreamp = c.preamp
            renderBypass = c.bypassed
        }
    }

    /// Apply preamp + biquad cascade to one (possibly interleaved) channel in place.
    /// - Parameters:
    ///   - channel: logical channel index (0-based)
    ///   - data: pointer to the first sample of this channel
    ///   - frames: number of frames to process
    ///   - stride: sample stride between frames (= channel count for interleaved)
    func process(channel: Int, data: UnsafeMutablePointer<Float>, frames: Int, stride: Int) {
        guard channel < Self.maxChannels else { return }
        let pre = renderPreamp
        let count = activeCount
        let base = channel * Self.maxBands

        var p = data
        if renderBypass {
            // Pass-through (no preamp, no EQ) for clean A/B comparison.
            return
        }

        for _ in 0..<frames {
            var x = p.pointee * pre
            var b = 0
            while b < count {
                let c = coeffBuf[b]
                let idx = base + b
                let y = c.b0 * x + z1[idx]
                z1[idx] = c.b1 * x - c.a1 * y + z2[idx]
                z2[idx] = c.b2 * x - c.a2 * y
                x = y
                b += 1
            }
            // Cheap denormal / NaN guard.
            if !x.isFinite { x = 0 }
            p.pointee = x
            p = p.advanced(by: stride)
        }
    }
}
