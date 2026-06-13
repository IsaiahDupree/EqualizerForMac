// Integration check of the real EQEngine.processMidSide. Compile WITH the engine sources:
//   swiftc -O Tools/verify_midside.swift \
//     Sources/SonanceEQ/DSP/EQEngine.swift Sources/SonanceEQ/DSP/FIRProcessor.swift \
//     Sources/SonanceEQ/DSP/FIRDesigner.swift Sources/SonanceEQ/DSP/FrequencyResponse.swift \
//     Sources/SonanceEQ/DSP/Biquad.swift Sources/SonanceEQ/Models/EQBand.swift -o /tmp/vms && /tmp/vms
//
// Verifies the Mid-Side decomposition:
//   • Mid EQ affects mono (L==R) content; Side EQ leaves it untouched.
//   • Side EQ affects anti-phase (L==-R) content; Mid EQ leaves it untouched.
import Accelerate
import Foundation

let kSubsystem = "verify"   // stand-in for the app global

@main
enum VerifyMidSide {
    static let fs = 48_000.0
    static let n = 48_000

    /// Run a stereo signal (given L,R generators) through the engine's Mid-Side path; return (Lgain, Rgain) dB.
    static func run(mid: [EQBand], side: [EQBand], l: (Int) -> Float, r: (Int) -> Float) -> (Double, Double) {
        let eq = EQEngine()
        eq.update(bands: mid, sideBands: side, preampDb: 0, bypassed: false,
                  sampleRate: fs, linearPhase: false, midSide: true)
        eq.resetState()     // seed coefficients immediately (no ramp) for a clean measurement
        eq.beginRender()

        var buf = [Float](repeating: 0, count: n * 2)   // interleaved stereo
        for i in 0..<n { buf[2 * i] = l(i); buf[2 * i + 1] = r(i) }

        // Process in realistic blocks (the engine caps a single call at maxFrames).
        let block = 4096
        buf.withUnsafeMutableBufferPointer { b in
            var off = 0
            while off < n {
                let f = min(block, n - off)
                eq.processMidSide(left: b.baseAddress! + 2 * off, right: b.baseAddress! + 2 * off + 1,
                                  frames: f, strideL: 2, strideR: 2)
                off += f
            }
        }

        // RMS gain per channel over the last half (settled).
        func gainDb(channelOffset: Int, ref: (Int) -> Float) -> Double {
            var so = 0.0, si = 0.0
            for i in (n / 2)..<n {
                let o = Double(buf[2 * i + channelOffset]); so += o * o
                let inp = Double(ref(i)); si += inp * inp
            }
            return 20 * log10((so).squareRoot() / max((si).squareRoot(), 1e-12))
        }
        return (gainDb(channelOffset: 0, ref: l), gainDb(channelOffset: 1, ref: r))
    }

    static func main() {
        let peak = [EQBand(frequency: 1000, gain: 6, q: 1.41, type: .peaking)]
        let flat: [EQBand] = []
        let sine: (Int) -> Float = { Float(sin(2.0 * .pi * 1000.0 * Double($0) / fs)) }
        let negSine: (Int) -> Float = { -Float(sin(2.0 * .pi * 1000.0 * Double($0) / fs)) }

        // 1. Mid EQ (+6dB) on a MONO signal (L==R): both channels boosted ~+6 dB.
        let (m1l, m1r) = run(mid: peak, side: flat, l: sine, r: sine)
        // 2. Side EQ (+6dB) on a MONO signal: no effect (S==0), ~0 dB.
        let (m2l, m2r) = run(mid: flat, side: peak, l: sine, r: sine)
        // 3. Side EQ (+6dB) on an ANTI-PHASE signal (L==-R): boosted ~+6 dB.
        let (m3l, m3r) = run(mid: flat, side: peak, l: sine, r: negSine)
        // 4. Mid EQ (+6dB) on an ANTI-PHASE signal: no effect (M==0), ~0 dB.
        let (m4l, m4r) = run(mid: peak, side: flat, l: sine, r: negSine)

        print(String(format: "1 Mid+6/mono       L %+.2f  R %+.2f  (expect +6, +6)", m1l, m1r))
        print(String(format: "2 Side+6/mono      L %+.2f  R %+.2f  (expect  0,  0)", m2l, m2r))
        print(String(format: "3 Side+6/antiphase L %+.2f  R %+.2f  (expect +6, +6)", m3l, m3r))
        print(String(format: "4 Mid+6/antiphase  L %+.2f  R %+.2f  (expect  0,  0)", m4l, m4r))

        func near(_ x: Double, _ t: Double) -> Bool { abs(x - t) < 0.3 }
        let ok = near(m1l, 6) && near(m1r, 6) && near(m2l, 0) && near(m2r, 0)
            && near(m3l, 6) && near(m3r, 6) && near(m4l, 0) && near(m4r, 0)
        print(ok ? "PASS — Mid-Side decomposition is correct." : "FAIL")
        exit(ok ? 0 : 1)
    }
}
