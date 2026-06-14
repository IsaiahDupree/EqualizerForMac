import Foundation

/// Expands one `EQBand` into the biquad section(s) that realize it.
///
/// Most shapes are a single RBJ biquad. **Low/High Cut** filters support a variable slope (à la
/// FabFilter Pro-Q): a slope of `S` dB/oct is a Butterworth filter of order `N = S/6`, realized as a
/// cascade of `⌊N/2⌋` second-order sections (with Butterworth Q values) plus one first-order section
/// when `N` is odd. So a single Low Cut band can emit up to 8 sections (96 dB/oct).
enum FilterDesigner {
    /// Discrete slopes offered for cut filters (dB/oct).
    static let slopes: [Double] = [6, 12, 18, 24, 36, 48, 72, 96]

    /// The biquad sections for a band at a given sample rate.
    static func sections(for band: EQBand, sampleRate: Double) -> [BiquadCoeffs] {
        switch band.type {
        case .lowPass, .highPass:
            return cutCascade(highPass: band.type == .highPass,
                              freq: band.frequency, sampleRate: sampleRate, slopeDbPerOct: band.slopeDbPerOct)
        default:
            return [RBJ.coeffs(type: band.type, sampleRate: sampleRate,
                               freq: band.frequency, gainDb: Double(band.gain), q: band.q)]
        }
    }

    // MARK: - Butterworth cut cascade

    private static func cutCascade(highPass: Bool, freq: Double, sampleRate: Double, slopeDbPerOct: Double) -> [BiquadCoeffs] {
        let order = max(1, Int((slopeDbPerOct / 6).rounded()))
        let type: FilterType = highPass ? .highPass : .lowPass
        var sections: [BiquadCoeffs] = []
        let (qs, hasFirstOrder) = butterworthSectionQs(order: order)
        for q in qs {
            sections.append(RBJ.coeffs(type: type, sampleRate: sampleRate, freq: freq, gainDb: 0, q: q))
        }
        if hasFirstOrder {
            sections.append(firstOrderSection(highPass: highPass, freq: freq, sampleRate: sampleRate))
        }
        return sections
    }

    /// Q values for the second-order sections of an order-`N` Butterworth filter (+ whether a
    /// first-order section remains, for odd orders).
    private static func butterworthSectionQs(order N: Int) -> (qs: [Double], hasFirstOrder: Bool) {
        if N % 2 == 0 {
            let m = N / 2
            let qs = (1...m).map { i in 1.0 / (2 * cos(Double(2 * i - 1) * .pi / Double(2 * N))) }
            return (qs, false)
        } else {
            let m = (N - 1) / 2
            let qs = m >= 1 ? (1...m).map { i in 1.0 / (2 * cos(Double(i) * .pi / Double(N))) } : []
            return (qs, true)
        }
    }

    /// First-order low/high pass via the bilinear transform (6 dB/oct).
    private static func firstOrderSection(highPass: Bool, freq: Double, sampleRate: Double) -> BiquadCoeffs {
        let fs = max(sampleRate, 1)
        let fc = min(max(freq, 1), fs * 0.5 - 1)
        let k = tan(.pi * fc / fs)
        let a1 = (k - 1) / (k + 1)
        if highPass {
            let b = 1 / (1 + k)
            return BiquadCoeffs(b0: Float(b), b1: Float(-b), b2: 0, a1: Float(a1), a2: 0)
        } else {
            let b = k / (1 + k)
            return BiquadCoeffs(b0: Float(b), b1: Float(b), b2: 0, a1: Float(a1), a2: 0)
        }
    }
}
