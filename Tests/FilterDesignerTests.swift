import Foundation
import Testing
@testable import SonanceEQ

@Suite struct FilterDesignerTests {
    // A cut filter's slope maps to the right number of cascaded biquad sections.
    static let sectionCounts: [[Double]] = [[6, 1], [12, 1], [18, 2], [24, 2], [36, 3], [48, 4], [72, 6], [96, 8]]
    @Test(arguments: sectionCounts)
    func cutSlopeExpandsToSections(_ c: [Double]) {
        let band = EQBand(frequency: 1000, gain: 0, q: 1, type: .lowPass, slopeDbPerOct: c[0])
        #expect(FilterDesigner.sections(for: band, sampleRate: kFs).count == Int(c[1]))
    }

    // Non-cut shapes are always a single section.
    @Test(arguments: [FilterType.peaking, .lowShelf, .highShelf, .notch, .bandPass, .allPass])
    func nonCutShapesAreSingleSection(_ type: FilterType) {
        let band = EQBand(frequency: 1000, gain: 3, q: 1, type: type)
        #expect(FilterDesigner.sections(for: band, sampleRate: kFs).count == 1)
    }

    // A high cut attenuates by ~slope dB one octave below its cutoff (Butterworth asymptote).
    // ~slope dB one octave from cutoff. Tolerance widens with order (Float precision across the cascade
    // at very deep attenuation: ~0.9 dB error at -96 dB is < 1%).
    @Test(arguments: [12.0, 24, 48, 96])
    func highCutSlopeAttenuation(_ slope: Double) {
        let band = EQBand(frequency: 1000, gain: 0, q: 1, type: .highPass, slopeDbPerOct: slope)
        #expect(abs(bandTotalDb(band, at: 500) - (-slope)) < 1.2)
    }

    @Test(arguments: [12.0, 24, 48, 96])
    func lowCutSlopeAttenuation(_ slope: Double) {
        let band = EQBand(frequency: 1000, gain: 0, q: 1, type: .lowPass, slopeDbPerOct: slope)
        #expect(abs(bandTotalDb(band, at: 2000) - (-slope)) < 1.2)
    }

    @Test func lowCutPassbandIsFlat() {
        let band = EQBand(frequency: 1000, gain: 0, q: 1, type: .lowPass, slopeDbPerOct: 48)
        #expect(abs(bandTotalDb(band, at: 100)) < 0.5)
    }

    @Test func highCutPassbandIsFlat() {
        let band = EQBand(frequency: 1000, gain: 0, q: 1, type: .highPass, slopeDbPerOct: 48)
        #expect(abs(bandTotalDb(band, at: 8000)) < 0.5)
    }

    // Every cut cascade is stable across all slopes.
    @Test(arguments: [6.0, 12, 18, 24, 36, 48, 72, 96])
    func cutCascadesAreStable(_ slope: Double) {
        let band = EQBand(frequency: 1000, gain: 0, q: 1, type: .highPass, slopeDbPerOct: slope)
        #expect(FilterDesigner.sections(for: band, sampleRate: kFs).allSatisfy(biquadStable))
    }

    // Constant-0 dB band-pass: unity at center, rejects far frequencies.
    @Test func bandPassUnityAtCenter() {
        let band = EQBand(frequency: 1000, gain: 0, q: 1, type: .bandPass)
        #expect(abs(bandTotalDb(band, at: 1000)) < 0.2)
    }

    @Test func bandPassRejectsAwayFromCenter() {
        let band = EQBand(frequency: 1000, gain: 0, q: 1, type: .bandPass)
        #expect(bandTotalDb(band, at: 8000) < -6)
        #expect(bandTotalDb(band, at: 125) < -6)
    }

    // All-pass: magnitude is flat (0 dB) everywhere; only phase changes.
    @Test(arguments: Grid.freqs)
    func allPassIsMagnitudeFlat(_ f: Double) {
        let band = EQBand(frequency: 1000, gain: 0, q: 1, type: .allPass)
        #expect(abs(bandTotalDb(band, at: f)) < 0.01)
    }

    // Default cut slope (12 dB/oct) reproduces the original single-section behavior.
    @Test func defaultSlopeIsTwelveDbPerOctave() {
        let band = EQBand(frequency: 1000, gain: 0, q: 1, type: .highPass)
        #expect(FilterDesigner.sections(for: band, sampleRate: kFs).count == 1)
        #expect(abs(bandTotalDb(band, at: 500) - (-12)) < 0.6)
    }
}
