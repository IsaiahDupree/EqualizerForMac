import Foundation

/// Supported biquad filter shapes (RBJ Audio EQ Cookbook).
enum FilterType: String, Codable, CaseIterable, Identifiable {
    case peaking
    case lowShelf
    case highShelf
    case lowPass
    case highPass
    case notch

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .peaking: return "PK"
        case .lowShelf: return "LSC"
        case .highShelf: return "HSC"
        case .lowPass: return "LP"
        case .highPass: return "HP"
        case .notch: return "NO"
        }
    }
}

/// Normalized direct-form biquad coefficients (a0 divided out).
struct BiquadCoeffs {
    var b0: Float = 1
    var b1: Float = 0
    var b2: Float = 0
    var a1: Float = 0
    var a2: Float = 0

    /// Identity (unity-gain pass-through) filter.
    static let identity = BiquadCoeffs()
}

/// Robert Bristow-Johnson "Audio EQ Cookbook" coefficient formulas.
/// Computed in double precision, stored as Float for the audio thread.
enum RBJ {
    static func coeffs(type: FilterType,
                       sampleRate: Double,
                       freq: Double,
                       gainDb: Double,
                       q: Double) -> BiquadCoeffs {
        let fs = max(sampleRate, 1)
        let f0 = min(max(freq, 1), fs * 0.5 - 1)   // clamp below Nyquist
        let qv = max(q, 0.0001)
        let A = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Double.pi * f0 / fs
        let cosw = cos(w0)
        let sinw = sin(w0)
        let alpha = sinw / (2.0 * qv)

        var b0 = 1.0, b1 = 0.0, b2 = 0.0
        var a0 = 1.0, a1 = 0.0, a2 = 0.0

        switch type {
        case .peaking:
            b0 = 1 + alpha * A
            b1 = -2 * cosw
            b2 = 1 - alpha * A
            a0 = 1 + alpha / A
            a1 = -2 * cosw
            a2 = 1 - alpha / A

        case .lowShelf:
            let s = 2 * sqrt(A) * alpha
            b0 = A * ((A + 1) - (A - 1) * cosw + s)
            b1 = 2 * A * ((A - 1) - (A + 1) * cosw)
            b2 = A * ((A + 1) - (A - 1) * cosw - s)
            a0 = (A + 1) + (A - 1) * cosw + s
            a1 = -2 * ((A - 1) + (A + 1) * cosw)
            a2 = (A + 1) + (A - 1) * cosw - s

        case .highShelf:
            let s = 2 * sqrt(A) * alpha
            b0 = A * ((A + 1) + (A - 1) * cosw + s)
            b1 = -2 * A * ((A - 1) + (A + 1) * cosw)
            b2 = A * ((A + 1) + (A - 1) * cosw - s)
            a0 = (A + 1) - (A - 1) * cosw + s
            a1 = 2 * ((A - 1) - (A + 1) * cosw)
            a2 = (A + 1) - (A - 1) * cosw - s

        case .lowPass:
            b0 = (1 - cosw) / 2
            b1 = 1 - cosw
            b2 = (1 - cosw) / 2
            a0 = 1 + alpha
            a1 = -2 * cosw
            a2 = 1 - alpha

        case .highPass:
            b0 = (1 + cosw) / 2
            b1 = -(1 + cosw)
            b2 = (1 + cosw) / 2
            a0 = 1 + alpha
            a1 = -2 * cosw
            a2 = 1 - alpha

        case .notch:
            b0 = 1
            b1 = -2 * cosw
            b2 = 1
            a0 = 1 + alpha
            a1 = -2 * cosw
            a2 = 1 - alpha
        }

        return BiquadCoeffs(b0: Float(b0 / a0),
                            b1: Float(b1 / a0),
                            b2: Float(b2 / a0),
                            a1: Float(a1 / a0),
                            a2: Float(a2 / a0))
    }
}
