// Offline check of FIRDesigner: compile WITH the real app sources so it tests shipping code:
//   swiftc -O Tools/verify_fir.swift \
//     Sources/SonanceEQ/DSP/FIRDesigner.swift Sources/SonanceEQ/DSP/FilterDesigner.swift \
//     Sources/SonanceEQ/DSP/FrequencyResponse.swift \
//     Sources/SonanceEQ/DSP/Biquad.swift Sources/SonanceEQ/Models/EQBand.swift -o /tmp/vfir && /tmp/vfir
//
// Verifies: (1) the impulse is symmetric → exactly linear phase; (2) the realized magnitude matches the
// IIR target (the curve the editor draws) within FIR design tolerance.
import Accelerate
import Foundation

@main
enum VerifyFIR {
    static let fs = 48_000.0
    static let L = 2048
    static let bands = [EQBand(frequency: 1000, gain: 6, q: 1.41, type: .peaking),
                        EQBand(frequency: 120,  gain: 4, q: 0.7,  type: .lowShelf)]

    /// Direct-convolution gain of the FIR at a tone (dB).
    static func firGainDb(_ h: [Float], _ tone: Double) -> Double {
        let n = L + 6000
        let x = (0..<n).map { Float(sin(2.0 * .pi * tone * Double($0) / fs)) }
        var sumOut = 0.0, sumIn = 0.0, cnt = 0.0
        for idx in L..<n {
            var acc: Float = 0
            for p in 0..<L { acc += h[p] * x[idx - p] }
            sumOut += Double(acc * acc); sumIn += Double(x[idx] * x[idx]); cnt += 1
        }
        return 20 * log10((sumOut / cnt).squareRoot() / (sumIn / cnt).squareRoot())
    }

    /// IIR target (what the editor curve shows) for comparison.
    static func targetDb(_ f: Double) -> Double {
        let w = 2 * Double.pi * f / fs
        return bands.map { FrequencyResponse.magnitudeDb(
            RBJ.coeffs(type: $0.type, sampleRate: fs, freq: $0.frequency, gainDb: Double($0.gain), q: $0.q), w) }
            .reduce(0, +)
    }

    static func main() {
        let h = FIRDesigner.design(bands: bands, preampDb: 0, sampleRate: fs, length: L, bypassed: false)

        // Symmetric about L/2 ⇒ h[n] == h[L-n] (h[0] is the lone unpaired wrap tap).
        var maxAsym = 0.0
        for n in 1..<L { maxAsym = max(maxAsym, Double(abs(h[n] - h[L - n]))) }
        print(String(format: "max symmetry error: %.2e  (linear-phase if ~0)", maxAsym))

        var worst = 0.0
        print("freq      FIR dB    target dB   Δ")
        for f in [60.0, 120, 300, 1000, 3000, 8000, 15000] {
            let fir = firGainDb(h, f), tgt = targetDb(f)
            worst = max(worst, abs(fir - tgt))
            print(String(format: "%6.0f   %+7.2f   %+8.2f   %+.2f", f, fir, tgt, fir - tgt))
        }
        let ok = maxAsym < 1e-6 && worst < 1.0
        print(ok ? "PASS — FIR is linear-phase and matches the target magnitude (≤1 dB)."
                 : String(format: "FAIL — worst magnitude error %.2f dB", worst))
        exit(ok ? 0 : 1)
    }
}
