import Foundation
@testable import SonanceEQ

let kFs = 48_000.0

/// Stability of a normalized biquad (a0 = 1): poles inside the unit circle ⇒ |a2| < 1 and |a1| < 1 + a2.
func biquadStable(_ c: BiquadCoeffs) -> Bool {
    let a1 = Double(c.a1), a2 = Double(c.a2)
    return a2 < 1 - 1e-9 && a2 > -1 - 1e-9 && abs(a1) < 1 + a2 + 1e-6
}

/// Magnitude (dB) of one RBJ band at `evalFreq`.
func bandDb(_ type: FilterType, freq: Double, gain: Double, q: Double, at evalFreq: Double, fs: Double = kFs) -> Double {
    let c = RBJ.coeffs(type: type, sampleRate: fs, freq: freq, gainDb: gain, q: q)
    return FrequencyResponse.magnitudeDb(c, 2 * .pi * evalFreq / fs)
}

/// Shared parameter grids.
enum Grid {
    static let freqs: [Double] = [31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let gains: [Double] = [-12, -9, -6, -3, 3, 6, 9, 12]
    static let qs: [Double] = [0.5, 0.707, 1.0, 1.414, 2.0, 4.0]
    static let types = FilterType.allCases

    static let freqGain: [[Double]] = freqs.flatMap { f in gains.map { [f, $0] } }            // 80
    static let freqQ: [[Double]] = freqs.flatMap { f in qs.map { [f, $0] } }                  // 60
    static let gainQ: [[Double]] = gains.flatMap { g in qs.map { [g, $0] } }                  // 48
    static let typeFreq: [(FilterType, Double)] = types.flatMap { t in freqs.map { (t, $0) } } // 60
    static let typeGain: [(FilterType, Double)] = types.flatMap { t in gains.map { (t, $0) } } // 48

    /// Exhaustive stability grid: every type × frequency × Q (gain fixed). 6×10×6 = 360.
    static let typeFreqQ: [[Double]] = types.enumerated().flatMap { (ti, _) in
        freqs.flatMap { f in qs.map { q in [Double(ti), f, q] } }
    }

    /// Peaking center-gain accuracy grid: frequency × Q × {+gain, -gain}. 10×6×2 = 120.
    static let peakCenter: [[Double]] = freqs.flatMap { f in
        qs.flatMap { q in [6.0, -6.0].map { g in [f, q, g] } }
    }
}
