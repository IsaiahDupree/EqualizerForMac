import Accelerate
import Foundation
import os

/// Real-time EQ processor: a per-channel cascade of biquads run by Accelerate's `vDSP_biquadm`.
///
/// Design (M2):
/// - **Control plane** (UI thread) calls `update(...)`, which computes the full section-major
///   coefficient array (preamp folded into section 0, bypass = identity) and stages it behind a lock,
///   bumping a generation counter.
/// - **Audio plane** (IOProc thread) calls `beginRender()` once per cycle. It *tries* (never blocks) to
///   pick up newly staged coefficients; if it does, it hands them to `vDSP_biquadm_SetTargetsDouble`,
///   which **ramps** the live filter toward the new values sample-by-sample — no zipper noise on slider
///   drags, preset switches, or bypass toggles. `process(channel:...)` then runs `vDSP_biquadm`.
///
/// The audio thread is wait-free: `beginRender()` uses `lockIfAvailable` (a try-lock), so if the control
/// thread is mid-write the cycle simply keeps ramping toward the previous targets. Coefficients are
/// computed in `update()` on the UI thread; the audio thread only memcpy's and sets targets — no
/// allocations, no blocking.
final class EQEngine {
    static let maxChannels = 8
    static let maxBands = 32
    private static let coeffsPerSection = 5            // b0, b1, b2, a1, a2
    private static var coeffCount: Int { coeffsPerSection * maxBands }

    /// How fast the filter ramps toward new targets (per-sample, 0…1). ~0.005 ≈ a few-ms glide at 48 kHz.
    private let interpolationRate: Float = 0.005
    /// Below this per-coefficient delta, targets are taken immediately (no ramp needed).
    private let coeffThreshold: Float = 1.0e-7

    // MARK: Control → audio staging (single-producer / single-consumer).

    private struct Staging {
        var coeffs: [Double]
        var generation: UInt64 = 1   // starts at 1 so the first beginRender applies it
    }
    private let staging: OSAllocatedUnfairLock<Staging>

    // MARK: Audio-thread-owned.

    private var setups: [vDSP_biquadm_Setup?]            // one M=1, N=maxBands setup per channel
    private var appliedGeneration: UInt64 = 0
    private let renderBuf: UnsafeMutablePointer<Double>  // scratch copy of staged coeffs

    private let log = Logger(subsystem: kSubsystem, category: "EQEngine")

    init() {
        staging = OSAllocatedUnfairLock(initialState: Staging(coeffs: Self.identityCoeffs()))
        renderBuf = .allocate(capacity: Self.coeffCount)
        renderBuf.initialize(repeating: 0, count: Self.coeffCount)
        setups = Array(repeating: nil, count: Self.maxChannels)
        createSetups(from: Self.identityCoeffs())
    }

    deinit {
        destroySetups()
        renderBuf.deallocate()
    }

    /// Identity (pass-through) coefficient array: every section is b0=1, rest 0.
    private static func identityCoeffs() -> [Double] {
        var c = [Double](repeating: 0, count: coeffCount)
        for s in 0..<maxBands { c[coeffsPerSection * s] = 1 }
        return c
    }

    private func createSetups(from coeffs: [Double]) {
        // vDSP_biquadm_CreateSetup(coeffs, M, N): M = sections, N = channels (the header's param
        // names are misleading — verified empirically, see Tools/verify_biquad.swift). One channel
        // per setup, maxBands cascaded sections; coefficients are section-major (5 per section).
        coeffs.withUnsafeBufferPointer { buf in
            for ch in 0..<Self.maxChannels {
                setups[ch] = vDSP_biquadm_CreateSetup(buf.baseAddress!, vDSP_Length(Self.maxBands), 1)
            }
        }
    }

    private func destroySetups() {
        for ch in 0..<Self.maxChannels {
            if let s = setups[ch] { vDSP_biquadm_DestroySetup(s) }
            setups[ch] = nil
        }
    }

    /// Reset filter delay memory (call when the stream restarts to avoid stale transients).
    /// Only invoked while the IOProc is stopped (engine build/rebuild), so it is safe to recreate the
    /// setups here. Setups are seeded with the latest staged coefficients applied immediately, so the
    /// first rendered block after a restart is already correct (no ramp-up from flat).
    func resetState() {
        let snapshot = staging.withLock { ($0.coeffs, $0.generation) }
        destroySetups()
        createSetups(from: snapshot.0)
        appliedGeneration = snapshot.1
    }

    // MARK: Control plane (UI thread)

    func update(bands: [EQBand], preampDb: Float, bypassed: Bool, sampleRate: Double) {
        var coeffs = Self.identityCoeffs()

        if !bypassed {
            var section = 0
            for band in bands where band.enabled {
                if section >= Self.maxBands { break }
                let c = RBJ.coeffs(type: band.type,
                                   sampleRate: sampleRate,
                                   freq: band.frequency,
                                   gainDb: Double(band.gain),
                                   q: band.q)
                let b = Self.coeffsPerSection * section
                coeffs[b + 0] = Double(c.b0)
                coeffs[b + 1] = Double(c.b1)
                coeffs[b + 2] = Double(c.b2)
                coeffs[b + 3] = Double(c.a1)
                coeffs[b + 4] = Double(c.a2)
                section += 1
            }
            // Fold preamp into section 0's feed-forward gains so it ramps with everything else.
            let preamp = Double(pow(10, preampDb / 20))
            coeffs[0] *= preamp
            coeffs[1] *= preamp
            coeffs[2] *= preamp
        }

        staging.withLock { s in
            s.coeffs = coeffs
            s.generation &+= 1
        }
    }

    // MARK: Audio plane (IOProc thread)

    /// Pick up newly staged coefficients (wait-free) and hand them to the ramping engine.
    /// Call once per render cycle before `process`.
    func beginRender() {
        var changed = false
        let seen: UInt64? = staging.withLockIfAvailable { s in
            if s.generation != appliedGeneration {
                s.coeffs.withUnsafeBufferPointer { renderBuf.update(from: $0.baseAddress!, count: $0.count) }
                changed = true
            }
            return s.generation
        }
        guard let seen, changed else { return }
        appliedGeneration = seen
        for ch in 0..<Self.maxChannels where setups[ch] != nil {
            vDSP_biquadm_SetTargetsDouble(setups[ch]!, renderBuf,
                                          interpolationRate, coeffThreshold,
                                          0, 0, vDSP_Length(Self.maxBands), 1)
        }
    }

    /// Apply the biquad cascade to one (possibly interleaved) channel in place.
    /// - Parameters:
    ///   - channel: logical channel index (0-based)
    ///   - data: pointer to the first sample of this channel
    ///   - frames: number of frames to process
    ///   - stride: sample stride between frames (= channel count for interleaved, 1 for planar)
    func process(channel: Int, data: UnsafeMutablePointer<Float>, frames: Int, stride: Int) {
        guard channel < Self.maxChannels, let setup = setups[channel] else { return }
        var input: UnsafePointer<Float> = UnsafePointer(data)
        var output: UnsafeMutablePointer<Float> = data
        vDSP_biquadm(setup,
                     &input, vDSP_Stride(stride),
                     &output, vDSP_Stride(stride),
                     vDSP_Length(frames))
    }
}
