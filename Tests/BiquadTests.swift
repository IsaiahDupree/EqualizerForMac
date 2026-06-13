import Foundation
import Testing
@testable import SonanceEQ

@Suite struct BiquadTests {

    @Test func identityIsUnityGain() {
        let c = BiquadCoeffs.identity
        #expect(c.b0 == 1 && c.b1 == 0 && c.b2 == 0 && c.a1 == 0 && c.a2 == 0)
    }

    // A peaking filter has exactly its set gain at its center frequency.
    @Test(arguments: Grid.freqGain)
    func peakingHitsCenterGain(_ fg: [Double]) {
        let db = bandDb(.peaking, freq: fg[0], gain: fg[1], q: 1.0, at: fg[0])
        #expect(abs(db - fg[1]) < 0.25)
    }

    // …regardless of Q.
    @Test(arguments: Grid.gainQ)
    func peakingCenterGainAcrossQ(_ gq: [Double]) {
        let db = bandDb(.peaking, freq: 1000, gain: gq[0], q: gq[1], at: 1000)
        #expect(abs(db - gq[0]) < 0.3)
    }

    // Every filter type is stable across the frequency grid.
    @Test(arguments: Grid.typeFreq)
    func filtersStableAcrossFrequency(_ tf: (FilterType, Double)) {
        let c = RBJ.coeffs(type: tf.0, sampleRate: kFs, freq: tf.1, gainDb: 6, q: 1.0)
        #expect(biquadStable(c))
    }

    // …and across extreme gains.
    @Test(arguments: Grid.typeGain)
    func filtersStableAcrossGain(_ tg: (FilterType, Double)) {
        let c = RBJ.coeffs(type: tg.0, sampleRate: kFs, freq: 1000, gainDb: tg.1, q: 2.0)
        #expect(biquadStable(c))
    }

    // Coefficients are always finite.
    @Test(arguments: Grid.typeFreq)
    func coefficientsFinite(_ tf: (FilterType, Double)) {
        let c = RBJ.coeffs(type: tf.0, sampleRate: kFs, freq: tf.1, gainDb: -9, q: 0.707)
        #expect(c.b0.isFinite && c.b1.isFinite && c.b2.isFinite && c.a1.isFinite && c.a2.isFinite)
    }

    // Low shelf approaches its set gain at DC (well below the corner).
    @Test(arguments: Grid.gains)
    func lowShelfGainAtDC(_ gain: Double) {
        let db = bandDb(.lowShelf, freq: 1000, gain: gain, q: 0.707, at: 30)
        #expect(abs(db - gain) < 0.6)
    }

    // High shelf approaches its set gain near Nyquist (well above the corner).
    @Test(arguments: Grid.gains)
    func highShelfGainAtTop(_ gain: Double) {
        let db = bandDb(.highShelf, freq: 1000, gain: gain, q: 0.707, at: 20000)
        #expect(abs(db - gain) < 0.6)
    }

    // A peaking filter is ~flat far from its center.
    @Test(arguments: [125.0, 250, 500, 1000, 2000, 4000])
    func peakingFlatFarFromCenter(_ f0: Double) {
        #expect(abs(bandDb(.peaking, freq: f0, gain: 12, q: 2.0, at: f0 / 16)) < 1.0)
        #expect(abs(bandDb(.peaking, freq: f0, gain: 12, q: 2.0, at: f0 * 16)) < 1.0)
    }

    // Frequency clamps below Nyquist (no blow-up requesting an out-of-range center).
    @Test(arguments: [20000.0, 24000, 30000, 48000])
    func frequencyClampedBelowNyquist(_ freq: Double) {
        let c = RBJ.coeffs(type: .peaking, sampleRate: kFs, freq: freq, gainDb: 6, q: 1)
        #expect(biquadStable(c) && c.b0.isFinite)
    }

    // A 0 dB peaking filter is the identity (flat everywhere).
    @Test(arguments: Grid.freqs)
    func zeroGainPeakingIsFlat(_ f0: Double) {
        #expect(abs(bandDb(.peaking, freq: f0, gain: 0, q: 1, at: f0)) < 0.001)
    }

    // A notch deeply attenuates its center frequency.
    @Test(arguments: [125.0, 250, 500, 1000, 2000, 4000, 8000])
    func notchAttenuatesCenter(_ f0: Double) {
        #expect(bandDb(.notch, freq: f0, gain: 0, q: 4, at: f0) < -20)
    }

    // A low-pass attenuates two octaves above its cutoff.
    @Test(arguments: [250.0, 500, 1000, 2000, 4000])
    func lowPassAttenuatesAboveCutoff(_ fc: Double) {
        #expect(bandDb(.lowPass, freq: fc, gain: 0, q: 0.707, at: fc * 4) < -6)
    }

    // A high-pass attenuates two octaves below its cutoff.
    @Test(arguments: [250.0, 500, 1000, 2000, 4000])
    func highPassAttenuatesBelowCutoff(_ fc: Double) {
        #expect(bandDb(.highPass, freq: fc, gain: 0, q: 0.707, at: fc / 4) < -6)
    }
}
