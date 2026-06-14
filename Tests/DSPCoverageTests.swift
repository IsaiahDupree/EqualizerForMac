import Accelerate
import Foundation
import Testing
@testable import SonanceEQ

// Broad parameterized coverage of the DSP layer. Each `arguments:` tuple is a separate test case, so
// these suites add several hundred property-based checks (finiteness, stability, gain accuracy, structure).

private let fs = 48_000.0
private let probeFreqs: [Double] = [50, 100, 250, 500, 1000, 2000, 4000, 8000, 12000]
private let centerFreqs: [Double] = [40, 80, 160, 320, 640, 1000, 2000, 4000, 8000, 15000]
private let gainsDb: [Double] = [-12, -9, -6, -3, -1, 1, 3, 6, 9, 12]
private let qValues: [Double] = [0.3, 0.5, 0.707, 1, 2, 4, 8]

private func isFinite(_ c: BiquadCoeffs) -> Bool {
    c.b0.isFinite && c.b1.isFinite && c.b2.isFinite && c.a1.isFinite && c.a2.isFinite
}

/// Sum of a band's section magnitudes (dB) at frequency `f`.
private func bandDb(_ band: EQBand, at f: Double) -> Double {
    let w = 2 * Double.pi * f / fs
    return FilterDesigner.sections(for: band, sampleRate: fs).reduce(0) { $0 + FrequencyResponse.magnitudeDb($1, w) }
}

@Suite struct RBJStabilityCoverage {
    /// Every RBJ filter is finite and stable (poles inside the unit circle: |a2| < 1) across the grid.
    @Test(arguments: FilterType.allCases, centerFreqs)
    func finiteAndStableByFreq(type: FilterType, freq: Double) {
        let c = RBJ.coeffs(type: type, sampleRate: fs, freq: freq, gainDb: 6, q: 1)
        #expect(isFinite(c))
        #expect(abs(Double(c.a2)) < 1.0 + 1e-3)
    }

    @Test(arguments: FilterType.allCases, qValues)
    func finiteAndStableByQ(type: FilterType, q: Double) {
        let c = RBJ.coeffs(type: type, sampleRate: fs, freq: 1000, gainDb: -6, q: q)
        #expect(isFinite(c))
        #expect(abs(Double(c.a2)) < 1.0 + 1e-3)
    }

    /// Clamping: requesting a frequency at/above Nyquist still yields finite, stable coefficients.
    @Test(arguments: FilterType.allCases, [23_900.0, 24_000.0, 30_000.0, 96_000.0])
    func nyquistClampStaysFinite(type: FilterType, freq: Double) {
        let c = RBJ.coeffs(type: type, sampleRate: fs, freq: freq, gainDb: 6, q: 1)
        #expect(isFinite(c))
        #expect(abs(Double(c.a2)) < 1.0 + 1e-3)
    }
}

@Suite struct PeakingResponseCoverage {
    /// A peaking filter's magnitude at its center frequency equals its gain (within rounding).
    @Test(arguments: gainsDb, probeFreqs)
    func centerGainMatches(gain: Double, freq: Double) {
        let c = RBJ.coeffs(type: .peaking, sampleRate: fs, freq: freq, gainDb: gain, q: 1)
        let w = 2 * Double.pi * freq / fs
        #expect(abs(FrequencyResponse.magnitudeDb(c, w) - gain) < 0.7)
    }

    /// Two octaves from the center, a narrow peaking filter is ~0 dB (transparent).
    @Test(arguments: gainsDb, [0.25, 4.0])   // two octaves below / above a 1 kHz band
    func transparentAwayFromCenter(gain: Double, factor: Double) {
        let band = EQBand(frequency: 1000, gain: Float(gain), q: 4, type: .peaking)
        #expect(abs(bandDb(band, at: 1000 * factor)) < 1.5)
    }
}

@Suite struct ShelfResponseCoverage {
    /// Shelves reach their full gain on the shelved side of the spectrum.
    @Test(arguments: gainsDb, [FilterType.lowShelf, FilterType.highShelf])
    func plateauGainMatches(gain: Double, type: FilterType) {
        let center = type == .lowShelf ? 4000.0 : 400.0
        let probe = type == .lowShelf ? 20.0 : 22_000.0
        let c = RBJ.coeffs(type: type, sampleRate: fs, freq: center, gainDb: gain, q: 0.707)
        let w = 2 * Double.pi * probe / fs
        #expect(abs(FrequencyResponse.magnitudeDb(c, w) - gain) < 1.2)
    }
}

@Suite struct NotchBandpassAllpassCoverage {
    /// A notch is deep at its center frequency. (The floor is set by Float coefficient precision, which
    /// degrades the ideal-infinite null toward ~-30 dB at very low frequencies where cos(w)→1.)
    @Test(arguments: Array(centerFreqs.dropLast()), qValues)
    func notchIsDeepAtCenter(freq: Double, q: Double) {
        let c = RBJ.coeffs(type: .notch, sampleRate: fs, freq: freq, gainDb: 0, q: q)
        let w = 2 * Double.pi * freq / fs
        #expect(FrequencyResponse.magnitudeDb(c, w) < -24)
    }

    /// A constant-peak-gain band-pass is 0 dB at its center frequency.
    @Test(arguments: Array(centerFreqs.dropLast()), qValues)
    func bandpassUnityAtCenter(freq: Double, q: Double) {
        let c = RBJ.coeffs(type: .bandPass, sampleRate: fs, freq: freq, gainDb: 0, q: q)
        let w = 2 * Double.pi * freq / fs
        #expect(abs(FrequencyResponse.magnitudeDb(c, w)) < 0.1)
    }

    /// An all-pass filter has unity magnitude at every frequency (it only shifts phase).
    @Test(arguments: [200.0, 1000.0, 4000.0, 9000.0], probeFreqs)
    func allpassIsFlat(center: Double, probe: Double) {
        let c = RBJ.coeffs(type: .allPass, sampleRate: fs, freq: center, gainDb: 0, q: 1)
        let w = 2 * Double.pi * probe / fs
        #expect(abs(FrequencyResponse.magnitudeDb(c, w)) < 0.01)
    }
}

@Suite struct CutCascadeCoverage {
    struct CutCase { let slope: Double; let sections: Int; let highPass: Bool }
    static let cases: [CutCase] = {
        let expected: [Double: Int] = [6: 1, 12: 1, 18: 2, 24: 2, 36: 3, 48: 4, 72: 6, 96: 8]
        return FilterDesigner.slopes.flatMap { s in
            [CutCase(slope: s, sections: expected[s]!, highPass: true),
             CutCase(slope: s, sections: expected[s]!, highPass: false)]
        }
    }()

    /// Each slope expands into the expected number of finite Butterworth sections.
    @Test(arguments: cases)
    func sectionCountMatches(c: CutCase) {
        let band = EQBand(frequency: 1000, gain: 0, q: 0.707,
                          type: c.highPass ? .highPass : .lowPass, slopeDbPerOct: c.slope)
        let sections = FilterDesigner.sections(for: band, sampleRate: fs)
        #expect(sections.count == c.sections)
        #expect(sections.allSatisfy(isFinite))
    }

    /// Near the cutoff a cut filter is ~ -3 dB·(order parity); well into the passband it's ~0 dB.
    @Test(arguments: FilterDesigner.slopes)
    func passbandIsFlat(slope: Double) {
        // High-pass passband is above the cutoff; probe two octaves up.
        let hp = EQBand(frequency: 500, gain: 0, q: 0.707, type: .highPass, slopeDbPerOct: slope)
        #expect(abs(bandDb(hp, at: 2000)) < 1.0)
        // Low-pass passband is below the cutoff; probe two octaves down.
        let lp = EQBand(frequency: 2000, gain: 0, q: 0.707, type: .lowPass, slopeDbPerOct: slope)
        #expect(abs(bandDb(lp, at: 500)) < 1.0)
    }

    /// Steeper slopes attenuate more in the stopband (monotonic in slope).
    @Test(arguments: Array(0..<(FilterDesigner.slopes.count - 1)))
    func steeperAttenuatesMore(i: Int) {
        let shallow = FilterDesigner.slopes[i], steep = FilterDesigner.slopes[i + 1]
        // High-pass at 1 kHz, probe one octave into the stopband (500 Hz).
        let a = EQBand(frequency: 1000, gain: 0, q: 0.707, type: .highPass, slopeDbPerOct: shallow)
        let b = EQBand(frequency: 1000, gain: 0, q: 0.707, type: .highPass, slopeDbPerOct: steep)
        #expect(bandDb(b, at: 500) <= bandDb(a, at: 500) + 0.5)
    }
}

@Suite struct FrequencyCurveCoverage {
    /// A flat graphic EQ produces a ~0 dB curve everywhere.
    @Test func flatCurveIsZero() {
        let curve = FrequencyResponse.curve(bands: Presets.flat, sampleRate: fs)
        #expect(curve.allSatisfy { abs($0.db) < 0.01 })
    }

    /// The curve is finite for every built-in preset at every supported rate.
    @Test(arguments: Presets.all, [44_100.0, 48_000.0, 96_000.0])
    func curveIsFinite(preset: Presets.Item, rate: Double) {
        let curve = FrequencyResponse.curve(bands: preset.bands, sampleRate: rate)
        #expect(curve.count == 220)
        #expect(curve.allSatisfy { $0.db.isFinite && $0.freq.isFinite })
    }

    /// Bass boost lifts the low end above the high end; treble boost does the opposite.
    @Test func tiltDirections() {
        let bass = FrequencyResponse.curve(bands: Presets.bassBoost, sampleRate: fs)
        #expect(bass.first!.db > bass.last!.db)
        let treble = FrequencyResponse.curve(bands: Presets.trebleBoost, sampleRate: fs)
        #expect(treble.last!.db > treble.first!.db)
    }
}

@Suite struct EngineProcessingCoverage {
    /// Drive a signal through the engine for every preset × rate and confirm the output stays finite/bounded.
    @Test(arguments: Presets.all, [44_100.0, 48_000.0, 96_000.0])
    func processedOutputIsFinite(preset: Presets.Item, rate: Double) {
        let engine = EQEngine()
        engine.update(bands: preset.bands, preampDb: 0, bypassed: false, sampleRate: rate)
        engine.resetState()   // apply staged coefficients immediately (IOProc-stopped path)

        let frames = 1024
        var buffer = (0..<frames).map { Float(sin(2 * Double.pi * 440 * Double($0) / rate)) }
        buffer.withUnsafeMutableBufferPointer { p in
            engine.process(channel: 0, data: p.baseAddress!, frames: frames, stride: 1)
        }
        #expect(buffer.allSatisfy { $0.isFinite && abs($0) < 100 })
    }

    /// Bypass is a true pass-through: output equals input sample-for-sample.
    @Test(arguments: [64, 128, 256, 512, 1024])
    func bypassIsIdentity(frames: Int) {
        let engine = EQEngine()
        engine.update(bands: Presets.loudness, preampDb: 6, bypassed: true, sampleRate: fs)
        engine.resetState()
        let input = (0..<frames).map { Float(sin(2 * Double.pi * 0.05 * Double($0))) }
        var output = input
        output.withUnsafeMutableBufferPointer { p in
            engine.process(channel: 0, data: p.baseAddress!, frames: frames, stride: 1)
        }
        for (a, b) in zip(input, output) { #expect(abs(a - b) < 1e-4) }
    }

    /// Mid-Side decode reconstructs the stereo pair exactly when the chains are pass-through.
    @Test(arguments: [64, 128, 256, 512, 1024])
    func midSideRoundTripIsLossless(frames: Int) {
        let engine = EQEngine()
        engine.update(bands: Presets.flat, sideBands: Presets.flat, preampDb: 0,
                      bypassed: true, sampleRate: fs, midSide: true)
        engine.resetState()
        let left = (0..<frames).map { Float(sin(2 * Double.pi * 0.03 * Double($0))) }
        let right = (0..<frames).map { Float(cos(2 * Double.pi * 0.07 * Double($0))) }
        var l = left, r = right
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                engine.processMidSide(left: lp.baseAddress!, right: rp.baseAddress!,
                                      frames: frames, strideL: 1, strideR: 1)
            }
        }
        for i in 0..<frames {
            #expect(abs(l[i] - left[i]) < 1e-4)
            #expect(abs(r[i] - right[i]) < 1e-4)
        }
    }
}
