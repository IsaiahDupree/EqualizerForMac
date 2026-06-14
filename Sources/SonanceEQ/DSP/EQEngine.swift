import Accelerate
import Foundation
import os

/// Real-time EQ processor: a per-channel cascade of biquads run by Accelerate's `vDSP_biquadm`,
/// with a linear-phase FIR alternative and a Mid-Side mode.
///
/// Design (M2):
/// - **Control plane** (UI thread) calls `update(...)`, which computes section-major coefficient arrays
///   for two chains — chain 0 (Mid / main) and chain 1 (Side) — preamp folded into section 0, bypass =
///   identity. In plain stereo both chains are identical. Staged behind a lock with a generation counter.
/// - **Audio plane** (IOProc thread) calls `beginRender()` once per cycle. It *tries* (never blocks) to
///   pick up newly staged coefficients; if it does, it hands them to `vDSP_biquadm_SetTargetsDouble`,
///   which **ramps** the live filter toward the new values — no zipper noise. Then either
///   `process(channel:)` (stereo/mono/multichannel) or `processMidSide(...)` (M/S stereo pair) runs.
///
/// Wait-free: `beginRender()` uses `withLockIfAvailable` (a try-lock), so the audio thread never blocks;
/// it keeps ramping toward the previous targets if the control thread is mid-write. No audio-thread allocs.
final class EQEngine {
    static let maxChannels = 8
    static let maxBands = 32
    private static let coeffsPerSection = 5            // b0, b1, b2, a1, a2
    private static var coeffCount: Int { coeffsPerSection * maxBands }
    private static let maxFrames = 8192

    private let interpolationRate: Float = 0.005
    private let coeffThreshold: Float = 1.0e-7

    // MARK: Control → audio staging (single-producer / single-consumer).

    private struct Staging {
        var midCoeffs: [Double]
        var sideCoeffs: [Double]
        var linearPhase: Bool = false
        var midSide: Bool = false
        var generation: UInt64 = 1   // starts at 1 so the first beginRender applies it
    }
    private let staging: OSAllocatedUnfairLock<Staging>

    /// Linear-phase (FIR) alternative to the IIR biquad path. Designed on the control thread.
    private let fir = FIRProcessor()

    // MARK: Audio-thread-owned.

    private var setups: [vDSP_biquadm_Setup?]            // setups[even]=Mid chain, setups[odd]=Side chain
    private var appliedGeneration: UInt64 = 0
    private var renderLinear = false
    private var renderMidSide = false
    private let renderMid: UnsafeMutablePointer<Double>
    private let renderSide: UnsafeMutablePointer<Double>
    private let midScratch: UnsafeMutablePointer<Float>  // M signal for processMidSide
    private let sideScratch: UnsafeMutablePointer<Float> // S signal

    private let log = Logger(subsystem: kSubsystem, category: "EQEngine")

    /// True when the audio path is currently decoding to Mid-Side (read on the audio thread after `beginRender`).
    var isMidSide: Bool { renderMidSide }

    init() {
        staging = OSAllocatedUnfairLock(initialState: Staging(midCoeffs: Self.identityCoeffs(),
                                                              sideCoeffs: Self.identityCoeffs()))
        renderMid = .allocate(capacity: Self.coeffCount); renderMid.initialize(repeating: 0, count: Self.coeffCount)
        renderSide = .allocate(capacity: Self.coeffCount); renderSide.initialize(repeating: 0, count: Self.coeffCount)
        midScratch = .allocate(capacity: Self.maxFrames); midScratch.initialize(repeating: 0, count: Self.maxFrames)
        sideScratch = .allocate(capacity: Self.maxFrames); sideScratch.initialize(repeating: 0, count: Self.maxFrames)
        setups = Array(repeating: nil, count: Self.maxChannels)
        createSetups(mid: Self.identityCoeffs(), side: Self.identityCoeffs())
    }

    deinit {
        destroySetups()
        renderMid.deallocate(); renderSide.deallocate()
        midScratch.deallocate(); sideScratch.deallocate()
    }

    private static func identityCoeffs() -> [Double] {
        var c = [Double](repeating: 0, count: coeffCount)
        for s in 0..<maxBands { c[coeffsPerSection * s] = 1 }
        return c
    }

    /// vDSP_biquadm_CreateSetup(coeffs, M, N): M = sections, N = channels (the header's param names are
    /// misleading — verified empirically, see Tools/verify_biquad.swift). Even channels get the Mid chain,
    /// odd channels the Side chain (identical in plain stereo).
    private func createSetups(mid: [Double], side: [Double]) {
        for ch in 0..<Self.maxChannels {
            let coeffs = (ch % 2 == 0) ? mid : side
            coeffs.withUnsafeBufferPointer {
                setups[ch] = vDSP_biquadm_CreateSetup($0.baseAddress!, vDSP_Length(Self.maxBands), 1)
            }
        }
    }

    private func destroySetups() {
        for ch in 0..<Self.maxChannels {
            if let s = setups[ch] { vDSP_biquadm_DestroySetup(s) }
            setups[ch] = nil
        }
    }

    /// Reset filter delay memory (call when the stream restarts to avoid stale transients). Only invoked
    /// while the IOProc is stopped (engine build/rebuild), seeded with the latest coefficients applied
    /// immediately so the first rendered block is already correct.
    func resetState() {
        let snapshot = staging.withLock { ($0.midCoeffs, $0.sideCoeffs, $0.generation) }
        destroySetups()
        createSetups(mid: snapshot.0, side: snapshot.1)
        appliedGeneration = snapshot.2
        fir.reset()
    }

    // MARK: Control plane (UI thread)

    /// Build the section-major coefficient array for one chain (preamp folded into section 0; bypass = identity).
    private func chainCoeffs(bands: [EQBand], preampDb: Float, bypassed: Bool, sampleRate: Double) -> [Double] {
        var coeffs = Self.identityCoeffs()
        guard !bypassed else { return coeffs }
        var section = 0
        outer: for band in bands where band.enabled {
            // A band may expand into several sections (e.g. a steep Low/High Cut).
            for c in FilterDesigner.sections(for: band, sampleRate: sampleRate) {
                if section >= Self.maxBands { break outer }
                let b = Self.coeffsPerSection * section
                coeffs[b + 0] = Double(c.b0); coeffs[b + 1] = Double(c.b1); coeffs[b + 2] = Double(c.b2)
                coeffs[b + 3] = Double(c.a1); coeffs[b + 4] = Double(c.a2)
                section += 1
            }
        }
        let preamp = Double(pow(10, preampDb / 20))
        coeffs[0] *= preamp; coeffs[1] *= preamp; coeffs[2] *= preamp
        return coeffs
    }

    /// Update both chains. In plain stereo, `sideBands` is ignored and the Side chain mirrors the Mid chain.
    func update(bands: [EQBand], sideBands: [EQBand] = [], preampDb: Float, bypassed: Bool,
                sampleRate: Double, linearPhase: Bool = false, midSide: Bool = false) {
        let mid = chainCoeffs(bands: bands, preampDb: preampDb, bypassed: bypassed, sampleRate: sampleRate)
        let side = midSide ? chainCoeffs(bands: sideBands, preampDb: preampDb, bypassed: bypassed, sampleRate: sampleRate)
                           : mid

        if linearPhase {
            let midFIR = FIRDesigner.design(bands: bands, preampDb: preampDb, sampleRate: sampleRate,
                                            length: FIRProcessor.length, bypassed: bypassed)
            let sideFIR = midSide ? FIRDesigner.design(bands: sideBands, preampDb: preampDb, sampleRate: sampleRate,
                                                       length: FIRProcessor.length, bypassed: bypassed)
                                  : midFIR
            fir.setFilters([midFIR, sideFIR])
        }

        staging.withLock { s in
            s.midCoeffs = mid
            s.sideCoeffs = side
            s.linearPhase = linearPhase
            s.midSide = midSide
            s.generation &+= 1
        }
    }

    // MARK: Audio plane (IOProc thread)

    /// Pick up newly staged coefficients (wait-free) and hand them to the ramping engine.
    private struct Pickup { var generation: UInt64; var changed: Bool; var linear: Bool; var midSide: Bool }

    func beginRender() {
        fir.beginRender()

        // Wait-free: if the control thread holds the lock, keep the previous render state for this cycle.
        let pickup: Pickup? = staging.withLockIfAvailable { s in
            var changed = false
            if s.generation != appliedGeneration {
                s.midCoeffs.withUnsafeBufferPointer { renderMid.update(from: $0.baseAddress!, count: $0.count) }
                s.sideCoeffs.withUnsafeBufferPointer { renderSide.update(from: $0.baseAddress!, count: $0.count) }
                changed = true
            }
            return Pickup(generation: s.generation, changed: changed, linear: s.linearPhase, midSide: s.midSide)
        }
        guard let pickup else { return }
        renderLinear = pickup.linear
        renderMidSide = pickup.midSide
        guard pickup.changed else { return }
        appliedGeneration = pickup.generation
        for ch in 0..<Self.maxChannels where setups[ch] != nil {
            let target = (ch % 2 == 0) ? renderMid : renderSide
            vDSP_biquadm_SetTargetsDouble(setups[ch]!, target,
                                          interpolationRate, coeffThreshold,
                                          0, 0, vDSP_Length(Self.maxBands), 1)
        }
    }

    /// Apply the chain for `channel` (even→Mid, odd→Side) to one channel in place. Used for stereo,
    /// mono, and multichannel (non-Mid-Side) layouts.
    func process(channel: Int, data: UnsafeMutablePointer<Float>, frames: Int, stride: Int) {
        if renderLinear {
            fir.process(channel: channel, data: data, frames: frames, stride: stride)
            return
        }
        guard channel < Self.maxChannels, let setup = setups[channel] else { return }
        var input: UnsafePointer<Float> = UnsafePointer(data)
        var output: UnsafeMutablePointer<Float> = data
        vDSP_biquadm(setup, &input, vDSP_Stride(stride), &output, vDSP_Stride(stride), vDSP_Length(frames))
    }

    /// Mid-Side: encode L/R → M=(L+R)/2, S=(L-R)/2; EQ M with the Mid chain and S with the Side chain;
    /// decode L=M+S, R=M-S. In place.
    func processMidSide(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
                        frames: Int, strideL: Int, strideR: Int) {
        guard frames > 0, frames <= Self.maxFrames else { return }

        var pl = left, pr = right
        for i in 0..<frames {
            let l = pl.pointee, r = pr.pointee
            midScratch[i] = (l + r) * 0.5
            sideScratch[i] = (l - r) * 0.5
            pl = pl.advanced(by: strideL); pr = pr.advanced(by: strideR)
        }

        if renderLinear {
            fir.process(channel: 0, data: midScratch, frames: frames, stride: 1)
            fir.process(channel: 1, data: sideScratch, frames: frames, stride: 1)
        } else {
            applyBiquad(setups[0], midScratch, frames)
            applyBiquad(setups[1], sideScratch, frames)
        }

        pl = left; pr = right
        for i in 0..<frames {
            let m = midScratch[i], s = sideScratch[i]
            pl.pointee = m + s
            pr.pointee = m - s
            pl = pl.advanced(by: strideL); pr = pr.advanced(by: strideR)
        }
    }

    private func applyBiquad(_ setup: vDSP_biquadm_Setup?, _ buffer: UnsafeMutablePointer<Float>, _ frames: Int) {
        guard let setup else { return }
        var input: UnsafePointer<Float> = UnsafePointer(buffer)
        var output: UnsafeMutablePointer<Float> = buffer
        vDSP_biquadm(setup, &input, 1, &output, 1, vDSP_Length(frames))
    }
}
