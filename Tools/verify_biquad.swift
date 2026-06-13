// Offline numerical check of the vDSP_biquadm path used by EQEngine.
// Mirrors the engine exactly: 32 identity sections, a peaking filter in section 0, M=1 setup,
// in-place processing. Verifies the frequency response matches RBJ theory (so the a1/a2 sign
// convention and section layout handed to vDSP_biquadm are correct).
//
// Run:  swift Tools/verify_biquad.swift
import Accelerate
import Foundation

let fs = 48_000.0
let sections = 32
let cps = 5

// RBJ peaking coefficients (copied from DSP/Biquad.swift), normalized by a0.
func peaking(freq: Double, gainDb: Double, q: Double) -> [Double] {
    let A = pow(10.0, gainDb / 40.0)
    let w0 = 2.0 * .pi * freq / fs
    let cosw = cos(w0), sinw = sin(w0)
    let alpha = sinw / (2.0 * q)
    let b0 = 1 + alpha * A, b1 = -2 * cosw, b2 = 1 - alpha * A
    let a0 = 1 + alpha / A, a1 = -2 * cosw, a2 = 1 - alpha / A
    return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
}

func makeCoeffs(freq: Double, gainDb: Double, q: Double) -> [Double] {
    var c = [Double](repeating: 0, count: cps * sections)
    for s in 0..<sections { c[cps * s] = 1 }       // identity sections
    let pk = peaking(freq: freq, gainDb: gainDb, q: q)
    for i in 0..<cps { c[i] = pk[i] }              // band in section 0
    return c
}

// Steady-state gain (amplitude ratio) the filter applies to a pure tone at `toneHz`.
func measuredGain(coeffs: [Double], toneHz: Double) -> Double {
    let n = 48_000
    var input = (0..<n).map { Float(sin(2.0 * .pi * toneHz * Double($0) / fs)) }
    var output = [Float](repeating: 0, count: n)

    // CreateSetup(coeffs, M, N): M = sections, N = channels (verified empirically — the header's
    // __M/__N names are misleading). One channel, `sections` cascaded sections.
    let setup = coeffs.withUnsafeBufferPointer {
        vDSP_biquadm_CreateSetup($0.baseAddress!, vDSP_Length(sections), 1)
    }!
    defer { vDSP_biquadm_DestroySetup(setup) }

    input.withUnsafeBufferPointer { inBuf in
        output.withUnsafeMutableBufferPointer { outBuf in
            var x: UnsafePointer<Float> = inBuf.baseAddress!
            var y: UnsafeMutablePointer<Float> = outBuf.baseAddress!
            vDSP_biquadm(setup, &x, 1, &y, 1, vDSP_Length(n))
        }
    }

    // RMS over the last half (skip the filter's startup transient).
    let tail = Array(output[(n/2)...])
    var rmsOut: Float = 0; vDSP_rmsqv(tail, 1, &rmsOut, vDSP_Length(tail.count))
    let tailIn = Array(input[(n/2)...])
    var rmsIn: Float = 0; vDSP_rmsqv(tailIn, 1, &rmsIn, vDSP_Length(tailIn.count))
    return Double(rmsOut / rmsIn)
}

func db(_ ratio: Double) -> Double { 20 * log10(ratio) }

// +6 dB peak at 1 kHz, Q 1.41.
let coeffs = makeCoeffs(freq: 1000, gainDb: 6, q: 1.41)
let atPeak = measuredGain(coeffs: coeffs, toneHz: 1000)
let belowBand = measuredGain(coeffs: coeffs, toneHz: 80)
let aboveBand = measuredGain(coeffs: coeffs, toneHz: 16000)

print(String(format: "1 kHz (target +6 dB):  %+.2f dB   (ratio %.3f)", db(atPeak), atPeak))
print(String(format: "80 Hz  (expect ~0 dB):  %+.2f dB", db(belowBand)))
print(String(format: "16 kHz (expect ~0 dB):  %+.2f dB", db(aboveBand)))

let ok = abs(db(atPeak) - 6) < 0.3 && abs(db(belowBand)) < 0.3 && abs(db(aboveBand)) < 0.3
print(ok ? "PASS — vDSP_biquadm path matches RBJ theory." : "FAIL — response does not match expectation.")
exit(ok ? 0 : 1)
