import Accelerate
import Foundation

/// Designs a **linear-phase** FIR filter whose magnitude matches the current EQ bands.
///
/// Method (frequency sampling):
/// 1. Sample the target magnitude (the same RBJ band cascade the IIR engine uses, plus preamp) on a
///    linear frequency grid 0…Nyquist.
/// 2. Treat it as a real, even (zero-phase) spectrum and inverse-DFT it → a real, even impulse centered
///    at n=0 (energy wraps to both ends of the buffer).
/// 3. Circularly shift by L/2 so it becomes a causal symmetric (Type-I) FIR — symmetric ⇒ exactly linear
///    phase, i.e. constant group delay of (L-1)/2 samples, no phase distortion.
/// 4. Apply a Blackman window to suppress truncation ripple.
///
/// The result is symmetric, so time-domain correlation (`vDSP_conv`) equals convolution — the processor
/// can use it directly without reversing.
enum FIRDesigner {
    /// Returns a length-`length` linear-phase FIR. `length` should be even (power-of-two preferred).
    /// `bypassed` returns a centered unit impulse (flat response, *same latency*) so A/B toggling in
    /// linear-phase mode stays click-free and time-aligned.
    static func design(bands: [EQBand],
                       preampDb: Float,
                       sampleRate: Double,
                       length: Int,
                       bypassed: Bool) -> [Float] {
        let L = length
        let center = (L - 1) / 2

        guard !bypassed else {
            var delta = [Float](repeating: 0, count: L)
            delta[center] = 1
            return delta
        }

        // --- 1. Target magnitude on a linear grid (zero-phase, hermitian-even). ---
        let coeffs = bands.filter(\.enabled).map {
            RBJ.coeffs(type: $0.type, sampleRate: sampleRate, freq: $0.frequency, gainDb: Double($0.gain), q: $0.q)
        }
        let preamp = pow(10.0, Double(preampDb) / 20.0)

        var real = [Double](repeating: 0, count: L)
        var imag = [Double](repeating: 0, count: L)
        let half = L / 2
        for k in 0...half {
            let f = Double(k) * sampleRate / Double(L)
            let w = 2 * Double.pi * f / sampleRate
            let db = coeffs.reduce(0.0) { $0 + FrequencyResponse.magnitudeDb($1, w) }
            let mag = preamp * pow(10.0, db / 20.0)
            real[k] = mag
            if k != 0 && k != half { real[L - k] = mag }   // mirror for a real, even spectrum
        }

        // --- 2. Inverse DFT → real, even impulse centered at 0. ---
        guard let setup = vDSP_DFT_zop_CreateSetupD(nil, vDSP_Length(L), .INVERSE) else {
            var delta = [Float](repeating: 0, count: L); delta[center] = 1; return delta
        }
        defer { vDSP_DFT_DestroySetupD(setup) }
        var outRe = [Double](repeating: 0, count: L)
        var outIm = [Double](repeating: 0, count: L)
        vDSP_DFT_ExecuteD(setup, real, imag, &outRe, &outIm)

        // --- 3. Shift by L/2 (→ causal, symmetric about L/2) + 4. Blackman window + normalize (1/L). ---
        // The Blackman window is centered at L/2 (w[n] == w[L-n]) to match the shifted impulse exactly,
        // so the result is precisely symmetric → exactly linear phase. (vDSP_blkman_window centers at
        // (L-1)/2, a half-sample off, which would skew the symmetry.)
        let scale = 1.0 / Double(L)
        let twoPi = 2.0 * Double.pi
        var h = [Float](repeating: 0, count: L)
        for n in 0..<L {
            let src = (n + half) % L         // undo the IDFT's centering-at-0
            let w = 0.42 - 0.5 * cos(twoPi * Double(n) / Double(L)) + 0.08 * cos(2 * twoPi * Double(n) / Double(L))
            h[n] = Float(outRe[src] * scale * w)
        }
        return h
    }
}
