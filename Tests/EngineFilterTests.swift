import Foundation
import Testing
@testable import SonanceEQ

/// End-to-end tests of the new filter shapes through the real vDSP_biquadm engine (not just the
/// FilterDesigner math) — including multi-section cut cascades.
@Suite struct EngineFilterTests {
    private func cut(_ type: FilterType, slope: Double) -> [EQBand] {
        [EQBand(frequency: 1000, gain: 0, q: 1, type: type, slopeDbPerOct: slope)]
    }

    // A high cut attenuates ~slope dB an octave below cutoff, when run through the engine.
    @Test(arguments: [12.0, 24, 48])
    func engineHighCutAttenuates(_ slope: Double) {
        let eq = primedEngine(cut(.highPass, slope: slope))
        #expect(abs(engineMonoGainDb(eq, toneHz: 500) - (-slope)) < 2.0)
    }

    @Test(arguments: [12.0, 24, 48])
    func engineLowCutAttenuates(_ slope: Double) {
        let eq = primedEngine(cut(.lowPass, slope: slope))
        #expect(abs(engineMonoGainDb(eq, toneHz: 2000) - (-slope)) < 2.0)
    }

    @Test func engineHighCutPassbandFlat() {
        let eq = primedEngine(cut(.highPass, slope: 24))
        #expect(abs(engineMonoGainDb(eq, toneHz: 4000)) < 0.6)
    }

    @Test func engineLowCutPassbandFlat() {
        let eq = primedEngine(cut(.lowPass, slope: 24))
        #expect(abs(engineMonoGainDb(eq, toneHz: 250)) < 0.6)
    }

    // The steepest cut (96 dB/oct = 8 cascaded sections) strongly attenuates through the engine.
    @Test func engineSteepCutWorks() {
        let eq = primedEngine(cut(.highPass, slope: 96))
        #expect(engineMonoGainDb(eq, toneHz: 500) < -40)
        #expect(abs(engineMonoGainDb(eq, toneHz: 8000)) < 0.6)   // passband flat
    }

    @Test func engineBandPass() {
        let eq = primedEngine([EQBand(frequency: 1000, gain: 0, q: 1, type: .bandPass)])
        #expect(abs(engineMonoGainDb(eq, toneHz: 1000)) < 0.5)   // unity at center
        #expect(engineMonoGainDb(eq, toneHz: 6000) < -6)         // rejects highs
    }

    // All-pass leaves magnitude unchanged at every frequency.
    @Test(arguments: [100.0, 500, 1000, 4000, 10000])
    func engineAllPassIsFlat(_ f: Double) {
        let eq = primedEngine([EQBand(frequency: 1000, gain: 0, q: 1, type: .allPass)])
        #expect(abs(engineMonoGainDb(eq, toneHz: f)) < 0.3)
    }

    // Many steep cuts request more sections than the engine has — must clamp, not crash.
    @Test func engineClampsOverBudgetWithoutCrashing() {
        let bands = (0..<10).map { EQBand(frequency: 200 + Double($0) * 150, gain: 0, q: 1, type: .highPass, slopeDbPerOct: 96) }
        let eq = primedEngine(bands)   // 10 × 8 = 80 sections requested, engine caps at 32
        #expect(engineMonoGainDb(eq, toneHz: 4000).isFinite)
    }
}
