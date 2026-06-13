import Foundation
import Testing
@testable import SonanceEQ

/// Run a mono tone through the engine's per-channel path and return the applied gain (dB).
func engineMonoGainDb(_ eq: EQEngine, toneHz: Double) -> Double {
    let n = 24000
    var buf = (0..<n).map { Float(sin(2.0 * .pi * toneHz * Double($0) / kFs)) }
    buf.withUnsafeMutableBufferPointer { b in
        var off = 0
        while off < n { let f = min(4096, n - off); eq.process(channel: 0, data: b.baseAddress! + off, frames: f, stride: 1); off += f }
    }
    var so = 0.0; for i in (n / 2)..<n { so += Double(buf[i] * buf[i]) }
    return 20 * log10((so / Double(n / 2)).squareRoot() / 0.7071)
}

/// Mid-Side gain on a stereo tone (L,R generators) → (L dB, R dB).
func engineMidSideGain(mid: [EQBand], side: [EQBand], l: (Int) -> Float, r: (Int) -> Float) -> (Double, Double) {
    let eq = EQEngine()
    eq.update(bands: mid, sideBands: side, preampDb: 0, bypassed: false, sampleRate: kFs, linearPhase: false, midSide: true)
    eq.resetState(); eq.beginRender()
    let n = 24000
    var buf = [Float](repeating: 0, count: n * 2)
    for i in 0..<n { buf[2 * i] = l(i); buf[2 * i + 1] = r(i) }
    buf.withUnsafeMutableBufferPointer { b in
        var off = 0
        while off < n {
            let f = min(4096, n - off)
            eq.processMidSide(left: b.baseAddress! + 2 * off, right: b.baseAddress! + 2 * off + 1, frames: f, strideL: 2, strideR: 2)
            off += f
        }
    }
    func gain(_ o: Int, _ ref: (Int) -> Float) -> Double {
        var so = 0.0, si = 0.0
        for i in (n / 2)..<n { so += Double(buf[2 * i + o] * buf[2 * i + o]); si += Double(ref(i) * ref(i)) }
        return 20 * log10((so).squareRoot() / max((si).squareRoot(), 1e-12))
    }
    return (gain(0, l), gain(1, r))
}

@Suite struct EngineTests {
    static let gainCases: [[Double]] = [125.0, 500, 1000, 4000].flatMap { f in
        [-9.0, -3, 3, 9].map { [f, $0] }
    }

    // The IIR path applies a peaking band's gain at its center frequency.
    @Test(arguments: gainCases)
    func processAppliesPeakingGain(_ fg: [Double]) {
        let eq = EQEngine()
        eq.update(bands: [EQBand(frequency: fg[0], gain: Float(fg[1]), q: 1, type: .peaking)],
                  preampDb: 0, bypassed: false, sampleRate: kFs)
        eq.resetState(); eq.beginRender()
        #expect(abs(engineMonoGainDb(eq, toneHz: fg[0]) - fg[1]) < 0.4)
    }

    // The linear-phase path applies the same gain.
    @Test(arguments: [250.0, 1000, 4000])
    func linearPhasePathAppliesGain(_ f: Double) {
        let eq = EQEngine()
        eq.update(bands: [EQBand(frequency: f, gain: 6, q: 1, type: .peaking)],
                  preampDb: 0, bypassed: false, sampleRate: kFs, linearPhase: true)
        eq.resetState(); eq.beginRender()
        #expect(abs(engineMonoGainDb(eq, toneHz: f) - 6) < 0.6)
    }

    @Test func bypassPassesThrough() {
        let eq = EQEngine()
        eq.update(bands: [EQBand(frequency: 1000, gain: 12, q: 1, type: .peaking)],
                  preampDb: 6, bypassed: true, sampleRate: kFs)
        eq.resetState(); eq.beginRender()
        #expect(abs(engineMonoGainDb(eq, toneHz: 1000)) < 0.1)
    }

    @Test func preampScalesOutput() {
        let eq = EQEngine()
        eq.update(bands: [], preampDb: -6, bypassed: false, sampleRate: kFs)
        eq.resetState(); eq.beginRender()
        #expect(abs(engineMonoGainDb(eq, toneHz: 1000) - (-6)) < 0.1)
    }

    @Test func tooManyBandsDoesNotCrash() {
        let eq = EQEngine()
        let many = (0..<40).map { EQBand(frequency: 100 + Double($0) * 100, gain: 1, q: 1, type: .peaking) }
        eq.update(bands: many, preampDb: 0, bypassed: false, sampleRate: kFs)
        eq.resetState(); eq.beginRender()
        #expect(engineMonoGainDb(eq, toneHz: 1000).isFinite)
    }

    // Mid-Side decomposition: Mid EQ acts on mono content, Side EQ on the stereo difference.
    static let midSideCases: [(Bool, Bool)] = [(true, false), (false, true)]  // (mono-signal, mid-eq)

    @Test func midEqAffectsMonoOnly() {
        let peak = [EQBand(frequency: 1000, gain: 6, q: 1, type: .peaking)]
        let sine: (Int) -> Float = { Float(sin(2.0 * .pi * 1000.0 * Double($0) / kFs)) }
        let (l, r) = engineMidSideGain(mid: peak, side: [], l: sine, r: sine)
        #expect(abs(l - 6) < 0.3 && abs(r - 6) < 0.3)
    }

    @Test func sideEqLeavesMonoUntouched() {
        let peak = [EQBand(frequency: 1000, gain: 6, q: 1, type: .peaking)]
        let sine: (Int) -> Float = { Float(sin(2.0 * .pi * 1000.0 * Double($0) / kFs)) }
        let (l, r) = engineMidSideGain(mid: [], side: peak, l: sine, r: sine)
        #expect(abs(l) < 0.3 && abs(r) < 0.3)
    }

    @Test func sideEqAffectsAntiPhase() {
        let peak = [EQBand(frequency: 1000, gain: 6, q: 1, type: .peaking)]
        let sine: (Int) -> Float = { Float(sin(2.0 * .pi * 1000.0 * Double($0) / kFs)) }
        let neg: (Int) -> Float = { -Float(sin(2.0 * .pi * 1000.0 * Double($0) / kFs)) }
        let (l, r) = engineMidSideGain(mid: [], side: peak, l: sine, r: neg)
        #expect(abs(l - 6) < 0.3 && abs(r - 6) < 0.3)
    }

    @Test func midEqLeavesAntiPhaseUntouched() {
        let peak = [EQBand(frequency: 1000, gain: 6, q: 1, type: .peaking)]
        let sine: (Int) -> Float = { Float(sin(2.0 * .pi * 1000.0 * Double($0) / kFs)) }
        let neg: (Int) -> Float = { -Float(sin(2.0 * .pi * 1000.0 * Double($0) / kFs)) }
        let (l, r) = engineMidSideGain(mid: peak, side: [], l: sine, r: neg)
        #expect(abs(l) < 0.3 && abs(r) < 0.3)
    }
}
