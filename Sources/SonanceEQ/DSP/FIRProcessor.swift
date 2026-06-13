import Accelerate
import Foundation
import os

/// Real-time **linear-phase** convolution engine (the FIR alternative to the IIR biquad path).
///
/// Streaming overlap method: per channel we keep the previous `L-1` input samples as history, prepend
/// them to the current block, and run `vDSP_conv` (which, for our symmetric filter, equals convolution).
/// Validated offline by `Tools/verify_fir.swift` (design) and a streaming/history equivalence check.
///
/// Two filter **slots** (0 = Mid/main, 1 = Side) support Mid-Side mode. A channel uses slot `channel % 2`;
/// in plain stereo both slots hold the same filter so every channel is identical.
///
/// Threading mirrors `EQEngine`: the control thread stages filters (`setFilter`); the audio thread picks
/// them up wait-free in `beginRender` (`withLockIfAvailable`). No allocations on the audio thread.
///
/// Latency: the filter is symmetric about `L/2`, so it adds a constant group delay of `L/2` samples
/// (~21 ms at 48 kHz for L=2048). That latency is inherent to linear-phase EQ and is surfaced in the UI.
final class FIRProcessor {
    static let length = 2048                    // FIR taps (power of two)
    static let maxChannels = EQEngine.maxChannels
    static let slots = 2                         // 0 = Mid/main, 1 = Side
    private static let maxFrames = 8192          // largest IOProc block we'll convolve in one pass

    private let L = length
    private let hist: UnsafeMutablePointer<Float>      // maxChannels × (L-1) previous input samples
    private let filterBuf: UnsafeMutablePointer<Float> // slots × L, audio-owned
    private let scratchA: UnsafeMutablePointer<Float>  // history ++ current input
    private let scratchC: UnsafeMutablePointer<Float>  // convolution output

    private struct Staged { var coeffs: [[Float]]; var gen: UInt64 = 1 }
    private let staged: OSAllocatedUnfairLock<Staged>
    private var appliedGen: UInt64 = 0
    private let log = Logger(subsystem: kSubsystem, category: "FIRProcessor")

    init() {
        let histCount = Self.maxChannels * (L - 1)
        hist = .allocate(capacity: histCount); hist.initialize(repeating: 0, count: histCount)

        filterBuf = .allocate(capacity: Self.slots * L)
        filterBuf.initialize(repeating: 0, count: Self.slots * L)
        for s in 0..<Self.slots { filterBuf[s * L + (L - 1) / 2] = 1 }   // centered delta = pass-through

        scratchA = .allocate(capacity: Self.maxFrames + L - 1)
        scratchA.initialize(repeating: 0, count: Self.maxFrames + L - 1)
        scratchC = .allocate(capacity: Self.maxFrames); scratchC.initialize(repeating: 0, count: Self.maxFrames)

        var delta = [Float](repeating: 0, count: L); delta[(L - 1) / 2] = 1
        staged = OSAllocatedUnfairLock(initialState: Staged(coeffs: Array(repeating: delta, count: Self.slots)))
    }

    deinit {
        hist.deallocate(); filterBuf.deallocate(); scratchA.deallocate(); scratchC.deallocate()
    }

    /// Stage freshly designed filters (control thread). `coeffs` must have `slots` entries of length L.
    func setFilters(_ coeffs: [[Float]]) {
        guard coeffs.count == Self.slots, coeffs.allSatisfy({ $0.count == L }) else { return }
        staged.withLock { $0.coeffs = coeffs; $0.gen &+= 1 }
    }

    /// Clear delay history (only while the IOProc is stopped — engine build/rebuild).
    func reset() {
        hist.update(repeating: 0, count: Self.maxChannels * (L - 1))
    }

    /// Pick up newly staged filters, wait-free. Call once per render cycle.
    func beginRender() {
        let result: (gen: UInt64, changed: Bool)? = staged.withLockIfAvailable { s in
            var changed = false
            if s.gen != appliedGen {
                for slot in 0..<Self.slots {
                    s.coeffs[slot].withUnsafeBufferPointer {
                        (filterBuf + slot * L).update(from: $0.baseAddress!, count: L)
                    }
                }
                changed = true
            }
            return (s.gen, changed)
        }
        if let result, result.changed { appliedGen = result.gen }
    }

    /// Convolve one channel in place, using filter slot `channel % slots`.
    func process(channel: Int, data: UnsafeMutablePointer<Float>, frames: Int, stride: Int) {
        guard channel < Self.maxChannels, frames > 0, frames <= Self.maxFrames else { return }
        let h = hist + channel * (L - 1)
        let filter = filterBuf + (channel % Self.slots) * L

        // scratchA = [history (L-1)] ++ [current input (frames)]
        scratchA.update(from: h, count: L - 1)
        var p = data
        for i in 0..<frames { scratchA[L - 1 + i] = p.pointee; p = p.advanced(by: stride) }

        // Symmetric filter ⇒ vDSP_conv (correlation) == convolution.
        vDSP_conv(scratchA, 1, filter, 1, scratchC, 1, vDSP_Length(frames), vDSP_Length(L))

        // Write output back (in place, respecting stride).
        p = data
        for i in 0..<frames { p.pointee = scratchC[i]; p = p.advanced(by: stride) }

        // New history = last (L-1) samples of the concatenated input.
        h.update(from: scratchA + frames, count: L - 1)
    }
}
