import Foundation
import Testing
@testable import SonanceEQ

@Suite struct FrequencyResponseTests {
    @Test(arguments: [32, 64, 128, 220, 512])
    func curveLengthMatchesPointCount(_ points: Int) {
        #expect(FrequencyResponse.curve(bands: [], sampleRate: kFs, points: points).count == points)
    }

    @Test(arguments: [32, 64, 128, 220, 512])
    func emptyBandsAreFlat(_ points: Int) {
        let curve = FrequencyResponse.curve(bands: [], sampleRate: kFs, points: points)
        #expect(curve.allSatisfy { abs($0.db) < 1e-9 })
    }

    @Test func frequenciesAreStrictlyAscending() {
        let curve = FrequencyResponse.curve(bands: [], sampleRate: kFs)
        #expect(zip(curve, curve.dropFirst()).allSatisfy { $0.freq < $1.freq })
    }

    @Test func endpointsCoverTheRange() {
        let curve = FrequencyResponse.curve(bands: [], sampleRate: kFs, fMin: 20, fMax: 20_000)
        #expect(abs(curve.first!.freq - 20) < 0.001)
        #expect(abs(curve.last!.freq - 20_000) < 0.001)
    }

    @Test func disabledBandsAreIgnored() {
        var off = EQBand(frequency: 1000, gain: 9, q: 1, type: .peaking)
        off.enabled = false
        let curve = FrequencyResponse.curve(bands: [off], sampleRate: kFs)
        #expect(curve.allSatisfy { abs($0.db) < 1e-9 })
    }

    // A single peaking band's curve peaks near its set gain.
    @Test(arguments: Grid.freqs)
    func singleBandPeaksNearGain(_ f0: Double) {
        let band = EQBand(frequency: f0, gain: 8, q: 1.4, type: .peaking)
        let maxDb = FrequencyResponse.curve(bands: [band], sampleRate: kFs, points: 512).map(\.db).max()!
        #expect(maxDb > 6.5 && maxDb < 8.1)
    }

    // The combined curve is the sample-wise sum of each band's curve (dB add). (10 freqs × 256 samples)
    @Test(arguments: Grid.freqs)
    func curveIsAdditiveInDecibels(_ f0: Double) {
        let b1 = EQBand(frequency: f0, gain: 5, q: 1.0, type: .peaking)
        let b2 = EQBand(frequency: 6000, gain: 3, q: 0.8, type: .highShelf)
        let points = 256
        let combined = FrequencyResponse.curve(bands: [b1, b2], sampleRate: kFs, points: points)
        let c1 = FrequencyResponse.curve(bands: [b1], sampleRate: kFs, points: points)
        let c2 = FrequencyResponse.curve(bands: [b2], sampleRate: kFs, points: points)
        for i in 0..<points {
            #expect(abs(combined[i].db - (c1[i].db + c2[i].db)) < 1e-6)
        }
    }

    @Test func allCurveValuesAreFinite() {
        let bands = [EQBand(frequency: 80, gain: 12, q: 3, type: .peaking),
                     EQBand(frequency: 12000, gain: -12, q: 0.5, type: .highShelf)]
        let curve = FrequencyResponse.curve(bands: bands, sampleRate: kFs)
        #expect(curve.allSatisfy { $0.db.isFinite && $0.freq.isFinite })
    }
}
