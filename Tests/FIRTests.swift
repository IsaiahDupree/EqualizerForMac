import Foundation
import Testing
@testable import SonanceEQ

@Suite struct FIRDesignerTests {
    static let configs: [[EQBand]] = [
        [EQBand(frequency: 1000, gain: 6, q: 1.0, type: .peaking)],
        [EQBand(frequency: 120, gain: 6, q: 0.7, type: .lowShelf)],
        [EQBand(frequency: 8000, gain: -6, q: 0.7, type: .highShelf)],
        [EQBand(frequency: 200, gain: 4, q: 1.0, type: .peaking),
         EQBand(frequency: 3000, gain: -3, q: 2.0, type: .peaking)],
    ]
    static let lengths = [512, 1024, 2048]

    static let symmetryCases: [(Int, Int)] =
        configs.indices.flatMap { ci in lengths.map { (ci, $0) } }

    // A linear-phase FIR is symmetric about L/2: h[n] == h[L-n].
    @Test(arguments: symmetryCases)
    func designIsSymmetric(_ args: (Int, Int)) {
        let (ci, L) = args
        let h = FIRDesigner.design(bands: Self.configs[ci], preampDb: 0, sampleRate: kFs, length: L, bypassed: false)
        #expect(h.count == L)
        var worst: Float = 0
        for n in 1..<L { worst = max(worst, abs(h[n] - h[L - n])) }
        #expect(worst < 1e-6)
    }

    // Bypass yields a centered unit impulse (flat response, same latency).
    @Test(arguments: lengths)
    func bypassIsCenteredDelta(_ L: Int) {
        let h = FIRDesigner.design(bands: [], preampDb: 0, sampleRate: kFs, length: L, bypassed: true)
        let center = (L - 1) / 2
        #expect(h[center] == 1)
        #expect(h.enumerated().allSatisfy { $0.offset == center || $0.element == 0 })
    }

    // The FIR realizes the target magnitude (coarse grid at short length).
    static let magCases: [(Int, Double)] = configs.indices.flatMap { ci in
        [300.0, 1000, 4000].map { (ci, $0) }
    }
    @Test(arguments: magCases)
    func designMatchesTargetMagnitude(_ args: (Int, Double)) {
        let (ci, f) = args
        let L = 1024
        let h = FIRDesigner.design(bands: Self.configs[ci], preampDb: 0, sampleRate: kFs, length: L, bypassed: false)
        let firDb = firGainDb(h, toneHz: f)
        let target = Self.configs[ci].reduce(0.0) {
            $0 + bandDb($1.type, freq: $1.frequency, gain: Double($1.gain), q: $1.q, at: f)
        }
        #expect(abs(firDb - target) < 1.5)
    }
}

@Suite struct FIRProcessorTests {
    // A delta filter (flat 0 dB EQ) passes a constant through at unity DC gain.
    @Test func flatDesignHasUnityDCGain() {
        let fir = FIRProcessor()
        let h = FIRDesigner.design(bands: [], preampDb: 0, sampleRate: kFs, length: FIRProcessor.length, bypassed: false)
        fir.setFilters([h, h])
        fir.beginRender()
        var buf = [Float](repeating: 1, count: 8000)
        buf.withUnsafeMutableBufferPointer { b in
            fir.process(channel: 0, data: b.baseAddress!, frames: 4096, stride: 1)
            fir.process(channel: 0, data: b.baseAddress! + 4096, frames: 8000 - 4096, stride: 1)
        }
        #expect(abs(buf[7999] - 1) < 0.05)   // settled DC output ≈ input
    }

    // A peaking-boost FIR raises a tone at its center frequency.
    @Test func boostFilterRaisesTone() {
        let fir = FIRProcessor()
        let h = FIRDesigner.design(bands: [EQBand(frequency: 1000, gain: 6, q: 1, type: .peaking)],
                                   preampDb: 0, sampleRate: kFs, length: FIRProcessor.length, bypassed: false)
        fir.setFilters([h, h])
        fir.beginRender()
        let n = 16000
        var buf = (0..<n).map { Float(sin(2.0 * .pi * 1000.0 * Double($0) / kFs)) }
        buf.withUnsafeMutableBufferPointer { b in
            var off = 0
            while off < n { let f = min(4096, n - off); fir.process(channel: 0, data: b.baseAddress! + off, frames: f, stride: 1); off += f }
        }
        var so = 0.0; for i in (n / 2)..<n { so += Double(buf[i] * buf[i]) }
        let db = 20 * log10((so / Double(n / 2)).squareRoot() / 0.7071)
        #expect(abs(db - 6) < 0.5)
    }
}

/// Direct-convolution gain (dB) of a FIR at a tone — for tests.
func firGainDb(_ h: [Float], toneHz: Double) -> Double {
    let L = h.count
    let n = L + 4000
    let x = (0..<n).map { Float(sin(2.0 * .pi * toneHz * Double($0) / kFs)) }
    var so = 0.0, si = 0.0
    for idx in L..<n {
        var acc: Float = 0
        for p in 0..<L { acc += h[p] * x[idx - p] }
        so += Double(acc * acc); si += Double(x[idx] * x[idx])
    }
    return 20 * log10((so).squareRoot() / max((si).squareRoot(), 1e-12))
}
