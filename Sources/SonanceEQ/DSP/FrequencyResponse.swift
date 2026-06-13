import Foundation

/// Computes the magnitude response of the EQ for plotting the parametric editor curve.
/// Evaluates each biquad's transfer function on the unit circle and sums in dB (a cascade is a
/// product of magnitudes → a sum of decibels). Preamp is intentionally excluded — it's a master
/// level, drawn separately, so band handles sit exactly on the curve.
enum FrequencyResponse {
    /// Magnitude (dB) of one normalized biquad at digital frequency `w = 2π·f/fs`.
    static func magnitudeDb(_ c: BiquadCoeffs, _ w: Double) -> Double {
        let cosw = cos(w), sinw = sin(w)
        let cos2 = cos(2 * w), sin2 = sin(2 * w)
        let numRe = Double(c.b0) + Double(c.b1) * cosw + Double(c.b2) * cos2
        let numIm = -(Double(c.b1) * sinw + Double(c.b2) * sin2)
        let denRe = 1 + Double(c.a1) * cosw + Double(c.a2) * cos2
        let denIm = -(Double(c.a1) * sinw + Double(c.a2) * sin2)
        let mag = (numRe * numRe + numIm * numIm).squareRoot()
            / max((denRe * denRe + denIm * denIm).squareRoot(), 1e-12)
        return 20 * log10(max(mag, 1e-9))
    }

    /// Combined response of all enabled bands over a log-spaced frequency grid.
    static func curve(bands: [EQBand],
                      sampleRate: Double,
                      points: Int = 220,
                      fMin: Double = 20,
                      fMax: Double = 20_000) -> [(freq: Double, db: Double)] {
        let coeffs = bands.filter(\.enabled).map {
            RBJ.coeffs(type: $0.type, sampleRate: sampleRate, freq: $0.frequency, gainDb: Double($0.gain), q: $0.q)
        }
        let logMin = log10(fMin), logMax = log10(fMax)
        return (0..<points).map { i in
            let f = pow(10, logMin + (logMax - logMin) * Double(i) / Double(points - 1))
            let w = 2 * Double.pi * f / sampleRate
            let db = coeffs.reduce(0.0) { $0 + magnitudeDb($1, w) }
            return (f, db)
        }
    }
}
