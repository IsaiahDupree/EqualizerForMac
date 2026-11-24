import AudioToolbox
import AVFAudio
import XCTest
@testable import SonanceEQiOS

/// Regression targets for the installed AUv3's samples and host lifecycle.
/// These tests do not claim a physical Bluetooth listening pass. Tolerances are
/// proposed project criteria and must be reviewed with the first Apple-runtime
/// results; do not weaken them just to hide a failing capture.
final class AudioContinuityTests: XCTestCase {
    private let variableBlocks: [AVAudioFrameCount] = [64, 127, 256, 511, 960, 1_024, 2_048, 31]

    @MainActor
    func testFlatAndBypassPreserveEverySampleAcrossRatesAndChannels() async throws {
        for rate in [44_100.0, 48_000.0, 96_000.0, 192_000.0] {
            for channelCount in [1, 2] {
                for bypassed in [false, true] {
                    let effect = try await installedEffect()
                    var settings = MobileEQSettings()
                    if bypassed {
                        settings.bands[5].gain = 12
                        settings.preamp = -18
                        settings.bypassed = true
                    }
                    settings.apply(to: try XCTUnwrap(effect.auAudioUnit.parameterTree))
                    let signal = QualitySignal.multitone(sampleRate: rate, channels: channelCount)
                    let stream = try QualityRenderStream(effect: effect, signal: signal)
                    defer { stream.close() }
                    let frames = Int(rate * 1.25) // Includes a source-loop boundary.
                    let capture = try stream.capture(frames: frames, blockPattern: variableBlocks)
                    let comparison = QualityComparison(actual: capture.samples, expected: signal.expected(frames: frames))
                    let label = "rate=\(rate), channels=\(channelCount), bypass=\(bypassed)"
                    XCTAssertTrue(comparison.passesUnityTolerance, "\(label): \(comparison.description)")
                    record(label, capture: capture, comparison: comparison)
                }
            }
        }
    }

    @MainActor
    func testStaticEQIsIndependentOfRenderBlockPartitionAndHasExpectedCenterGain() async throws {
        let rate = 48_000.0
        let signal = QualitySignal.multitone(sampleRate: rate, channels: 2)
        let settings = MobileEQSettings(bands: [
            EQBand(frequency: 120, gain: 3, q: 0.707, type: .lowShelf),
            EQBand(frequency: 1_000, gain: -4, q: 1.2, type: .peaking),
            EQBand(frequency: 8_000, gain: 2, q: 0.707, type: .highShelf),
        ], preamp: -8)
        let regular = try await render(signal, settings: settings, frames: 72_000, pattern: [512])
        let varied = try await render(signal, settings: settings, frames: 72_000, pattern: variableBlocks)
        let comparison = QualityComparison(actual: varied.samples, expected: regular.samples)
        XCTAssertTrue(comparison.passesUnityTolerance, comparison.description)
        record("static EQ: fixed vs variable blocks", capture: varied, comparison: comparison)

        // Independent analytic expectation: a +6 dB peaking filter is +6 dB
        // at its center. The -9 dB preamp therefore gives -3 dB overall.
        // This does not call FrequencyResponse or copy the filter implementation.
        let tone = QualitySignal.tones(sampleRate: rate, frequencies: [1_000])
        let center = MobileEQSettings(bands: [EQBand(frequency: 1_000, gain: 6, q: 1, type: .peaking)], preamp: -9)
        let output = try await render(tone, settings: center, frames: 48_000, pattern: variableBlocks)
        let inputRMS = 0.125 / sqrt(2.0)
        XCTAssertEqual(20 * log10(output.rms(channel: 0, dropping: 24_000) / inputRMS), -3, accuracy: 0.15)
        XCTAssertEqual(output.nonFiniteSamples, 0)
    }

    @MainActor
    func testStereoChannelsRemainIndependent() async throws {
        for activeChannel in [0, 1] {
            let frequencies: [Double?] = activeChannel == 0 ? [997, nil] : [nil, 997]
            let signal = QualitySignal.tones(sampleRate: 48_000, frequencies: frequencies)
            let settings = MobileEQSettings(bands: [EQBand(frequency: 997, gain: 6, q: 1, type: .peaking)], preamp: -9)
            let output = try await render(signal, settings: settings, frames: 48_000, pattern: variableBlocks)
            XCTAssertEqual(output.nonFiniteSamples, 0)
            let silentChannel = 1 - activeChannel
            let silentPeak = output.samples[silentChannel].reduce(0.0) { max($0, abs(Double($1))) }
            XCTAssertLessThanOrEqual(silentPeak, 1e-7, "Unexpected leakage into channel \(silentChannel)")
            // Use the second half-second; this is a finite-window RMS bound.
            let gainDB = 20 * log10(output.rms(channel: activeChannel, dropping: 24_000) / (0.125 / sqrt(2.0)))
            XCTAssertEqual(gainDB, -3, accuracy: 0.15)
        }
    }

    @MainActor
    func testMidSideCurvesProcessCenterAndSideIndependently() async throws {
        var settings = MobileEQSettings(bands: [
            EQBand(frequency: 997, gain: 6, q: 1, type: .peaking),
        ])
        settings.sideBands = []
        settings.midSideEnabled = true

        let inPhase = QualitySignal.tones(sampleRate: 48_000, frequencies: [997, 997])
        let centerOutput = try await render(inPhase, settings: settings, frames: 48_000, pattern: variableBlocks)
        XCTAssertEqual(centerOutput.nonFiniteSamples, 0)
        for channel in 0..<2 {
            XCTAssertEqual(20 * log10(centerOutput.rms(channel: channel, dropping: 24_000) / (0.125 / sqrt(2.0))),
                           6, accuracy: 0.2)
        }

        var antiPhaseChannels = inPhase.channels
        antiPhaseChannels[1] = antiPhaseChannels[1].map { -$0 }
        let antiPhase = QualitySignal(sampleRate: 48_000, channels: antiPhaseChannels)
        let sideOutput = try await render(antiPhase, settings: settings, frames: 48_000, pattern: variableBlocks)
        XCTAssertEqual(sideOutput.nonFiniteSamples, 0)
        XCTAssertEqual(20 * log10(sideOutput.rms(channel: 0, dropping: 24_000) / (0.125 / sqrt(2.0))),
                       0, accuracy: 0.2)
        XCTAssertEqual(20 * log10(sideOutput.rms(channel: 1, dropping: 24_000) / (0.125 / sqrt(2.0))),
                       0, accuracy: 0.2)
        let phaseResidual = zip(sideOutput.samples[0], sideOutput.samples[1]).map { abs($0 + $1) }.max() ?? 1
        XCTAssertEqual(phaseResidual, 0, accuracy: 1e-6, "An anti-phase Side signal must remain anti-phase")

        var sideOnly = settings
        sideOnly.bands = []
        sideOnly.sideBands = [EQBand(frequency: 997, gain: 6, q: 1, type: .peaking)]
        let sideBoost = try await render(antiPhase, settings: sideOnly, frames: 48_000, pattern: variableBlocks)
        XCTAssertEqual(20 * log10(sideBoost.rms(channel: 0, dropping: 24_000) / (0.125 / sqrt(2.0))),
                       6, accuracy: 0.2)
        XCTAssertEqual(20 * log10(sideBoost.rms(channel: 1, dropping: 24_000) / (0.125 / sqrt(2.0))),
                       6, accuracy: 0.2)
    }

    @MainActor
    func testLinearPhaseFIRBypassKeepsItsDocumentedDelayAndZeroesInputTail() async throws {
        let rate = 48_000.0
        var impulse = [Float](repeating: 0, count: Int(rate))
        impulse[0] = 0.5
        let signal = QualitySignal(sampleRate: rate, channels: [impulse])
        let settings = MobileEQSettings(bands: [], preamp: 0, bypassed: true, linearPhaseEnabled: true)
        let capture = try await render(signal, settings: settings, frames: 4_096, pattern: variableBlocks)
        XCTAssertEqual(capture.nonFiniteSamples, 0)
        XCTAssertEqual(capture.samples[0][1_023], 0, accuracy: 1e-7)
        XCTAssertEqual(capture.samples[0][1_024], 0.5, accuracy: 1e-6)
        XCTAssertEqual(capture.samples[0].dropFirst(1_025).map { abs($0) }.max() ?? 1, 0, accuracy: 1e-7)
    }

    @MainActor
    func testLinearPhaseIgnoresBandsAboveTheCurrentNyquistFrequency() async throws {
        let rate = 8_000.0
        let signal = QualitySignal.tones(sampleRate: rate, frequencies: [1_000])
        let settings = MobileEQSettings(bands: [
            EQBand(frequency: 18_000, gain: 12, q: 1, type: .peaking),
        ], linearPhaseEnabled: true)
        let capture = try await render(signal, settings: settings, frames: 8_000, pattern: [127, 256, 511])
        XCTAssertEqual(capture.nonFiniteSamples, 0)
        XCTAssertEqual(20 * log10(capture.rms(channel: 0, dropping: 4_000) / (0.125 / sqrt(2.0))),
                       0, accuracy: 0.2)
    }

    @MainActor
    func testSameAudioUnitSurvivesHostFormatReallocationWithoutLosingState() async throws {
        let effect = try await installedEffect()
        let tree = try XCTUnwrap(effect.auAudioUnit.parameterTree)
        let settings = MobileEQSettings(bands: [], preamp: -6)
        settings.apply(to: tree)
        let configurations: [(Double, Int)] = [(44_100, 2), (48_000, 2), (16_000, 1), (96_000, 2), (48_000, 1)]
        for (rate, channels) in configurations {
            let signal = QualitySignal.tones(sampleRate: rate, frequencies: Array(repeating: 1_000, count: channels))
            let stream = try QualityRenderStream(effect: effect, signal: signal)
            let frames = Int(rate / 2)
            let capture = try stream.capture(frames: frames, blockPattern: variableBlocks)
            let comparison = QualityComparison(actual: capture.samples,
                                                expected: signal.expected(frames: frames, gain: pow(10, -6.0 / 20)))
            XCTAssertTrue(comparison.passesUnityTolerance, "\(rate) Hz / \(channels) ch: \(comparison.description)")
            XCTAssertEqual(try XCTUnwrap(tree.parameter(withAddress: MobileEQ.preampAddress)).value, -6)
            XCTAssertEqual(try XCTUnwrap(tree.parameter(withAddress: MobileEQ.bandCountAddress)).value, 0)
            record("host reallocation \(rate) Hz / \(channels) ch", capture: capture, comparison: comparison)
            stream.close() // Detach before the same AU is attached to another host engine.
        }
    }

    @MainActor
    func testMaximumBandCascadeKeepsAllBlocksFiniteAndAudibleWithHeadroom() async throws {
        // Each 96 dB/oct high-pass uses eight sections, exercising all 256
        // available sections. The tones are well inside the pass band; this
        // avoids misclassifying an intended EQ cut as an unexpected dropout.
        let bands = (0..<MobileEQ.maximumBandCount).map { _ in
            EQBand(frequency: 400, gain: 0, q: 0.707, type: .highPass, slopeDbPerOct: 96)
        }
        let settings = MobileEQSettings(bands: bands, preamp: -12)
        XCTAssertTrue(settings.isValid)
        let signal = QualitySignal.tones(sampleRate: 48_000, frequencies: [1_000, 3_000])
        let output = try await render(signal, settings: settings, frames: 144_000, pattern: variableBlocks)
        XCTAssertEqual(output.nonFiniteSamples, 0)
        XCTAssertLessThan(output.peak, 0.95, "Controlled fixture should retain digital peak headroom")
        for channel in 0..<2 {
            XCTAssertEqual(output.samples[channel].count, 144_000)
            // One second is explicitly reserved for the long cascade's startup
            // transient. Its samples above are still checked for finite peaks.
            XCTAssertEqual(output.knownToneGapWindowCount(channel: channel, dropping: 48_000), 0)
            XCTAssertEqual(20 * log10(output.rms(channel: channel, dropping: 48_000) / (0.125 / sqrt(2.0))),
                           -12, accuracy: 0.3)
        }
        record("32 bands / 256 sections / 3 seconds of signal", capture: output)
    }

    @MainActor
    func testSupportedGainAndBypassEditsKeepTheKnownToneContinuous() async throws {
        let effect = try await installedEffect()
        let tree = try XCTUnwrap(effect.auAudioUnit.parameterTree)
        let settings = MobileEQSettings(bands: [
            EQBand(frequency: 1_000, gain: 0, q: 1, type: .peaking),
        ], preamp: -12)
        settings.apply(to: tree)
        let gain = try XCTUnwrap(tree.parameter(withAddress: MobileEQ.address(.gain, band: 0)))
        let signal = QualitySignal.tones(sampleRate: 48_000, frequencies: [1_000])
        let stream = try QualityRenderStream(effect: effect, signal: signal)
        defer { stream.close() }

        // Supported parameter-tree/UI changes between captures. This does not
        // send sample-accurate automation events, which this AU does not promise.
        let edits: [(gain: Float, bypassed: Bool)] = [(-6, false), (6, false), (0, true), (3, false), (-3, false)]
        for edit in edits {
            gain.value = edit.gain
            effect.auAudioUnit.shouldBypassEffect = edit.bypassed
            let capture = try stream.capture(frames: 24_000, blockPattern: variableBlocks)
            XCTAssertEqual(capture.nonFiniteSamples, 0)
            XCTAssertLessThan(capture.peak, 0.95)
            // Inspect the entire transition, not just its settled ending.
            // The shared detector uses overlapping 2 ms windows, so a 5 ms
            // mute cannot hide across a window boundary. It is calibrated to
            // these known tones, not a universal click/audibility metric.
            XCTAssertEqual(capture.knownToneGapWindowCount(channel: 0), 0)
            let expectedGain = edit.bypassed ? 0 : Double(edit.gain) - 12
            let measuredGain = 20 * log10(capture.rms(channel: 0, dropping: 12_000) / (0.125 / sqrt(2.0)))
            XCTAssertEqual(measuredGain, expectedGain, accuracy: 0.2,
                           "The settled result must follow the requested edit")
            record("UI edit gain=\(edit.gain), bypass=\(edit.bypassed)", capture: capture)
        }
    }

    @MainActor
    func testStrongBassFixturePreservesExpectedGainWithExplicitHeadroom() async throws {
        // Controlled analogue of the user's large bass boost. It tests Sonance,
        // not Pragmatic's implementation or the user's entire saved profile.
        // At the bell's center: +17.4 dB EQ -18.4 dB preamp = -1 dB net.
        let settings = MobileEQSettings(bands: [
            EQBand(frequency: 40, gain: 17.4, q: 0.71, type: .peaking),
        ], preamp: -18.4)
        XCTAssertTrue(settings.isValid)
        for amplitude in [0.5, 0.9] {
            let signal = QualitySignal.tones(sampleRate: 48_000, frequencies: [40], amplitude: amplitude)
            let capture = try await render(signal, settings: settings, frames: 96_000, pattern: variableBlocks)
            XCTAssertEqual(capture.nonFiniteSamples, 0)
            XCTAssertLessThan(capture.peak, 1, "This specified fixture must not digitally clip, including startup")
            let gainDB = 20 * log10(capture.rms(channel: 0, dropping: 48_000) / (amplitude / sqrt(2.0)))
            XCTAssertEqual(gainDB, -1, accuracy: 0.25)
            record("40 Hz / +17.4 dB bell / -18.4 dB preamp / input peak \(amplitude)", capture: capture)
        }
        // Passing tones do not establish true-peak headroom for all music, or
        // prove any Bluetooth codec, acoustic, limiter, or dropout behavior.
    }

    func testQualityComparisonDetectsInjectedGapsCorruptionAndChannelChanges() {
        let reference = QualitySignal.multitone(sampleRate: 48_000, channels: 2).expected(frames: 24_000)
        XCTAssertTrue(QualityComparison(actual: reference, expected: reference).passesUnityTolerance)

        var gap = reference
        for channel in gap.indices { gap[channel].replaceSubrange(5_000..<5_240, with: repeatElement(Float(0), count: 240)) }
        XCTAssertFalse(QualityComparison(actual: gap, expected: reference).passesUnityTolerance,
                       "A five-millisecond silent insertion must fail even if final RMS looks normal")

        var duplicate = reference
        for channel in duplicate.indices {
            duplicate[channel].replaceSubrange(5_000..<5_127, with: reference[channel][4_873..<5_000])
        }
        XCTAssertFalse(QualityComparison(actual: duplicate, expected: reference).passesUnityTolerance)
        XCTAssertFalse(QualityComparison(actual: [reference[1], reference[0]], expected: reference).passesUnityTolerance)

        var corrupt = reference
        corrupt[0][8_000] = .nan
        XCTAssertFalse(QualityComparison(actual: corrupt, expected: reference).passesUnityTolerance)
        corrupt = reference
        corrupt[0][8_000] = 1.1
        XCTAssertFalse(QualityComparison(actual: corrupt, expected: reference).passesUnityTolerance)
        var shortened = reference
        shortened[0].removeLast()
        XCTAssertFalse(QualityComparison(actual: shortened, expected: reference).passesUnityTolerance)

        // Validate the EXACT detector used by the live-edit and maximum-band
        // cases, not only the stricter unity-reference sample comparison above.
        let toneReference = QualitySignal.tones(sampleRate: 48_000, frequencies: [1_000, 3_000])
            .expected(frames: 24_000, gain: pow(10, -12.0 / 20))
        let intact = QualityCapture(samples: toneReference, sampleRate: 48_000, offlineContextRetries: 0)
        for channel in 0..<2 {
            XCTAssertEqual(intact.knownToneGapWindowCount(channel: channel), 0,
                           "Normal tone zero crossings must not be called gaps")
            // A short mute inside one old window, plus a mute crossing the
            // former disjoint 480-frame window grid, must both be detected.
            for missingFrames in [5_000..<5_240, 5_040..<5_520] {
                var muted = toneReference
                muted[channel].replaceSubrange(missingFrames,
                    with: repeatElement(Float(0), count: missingFrames.count))
                let fault = QualityCapture(samples: muted, sampleRate: 48_000, offlineContextRetries: 0)
                XCTAssertGreaterThan(fault.knownToneGapWindowCount(channel: channel), 0,
                    "Must detect \(missingFrames.count)-frame mute at \(missingFrames.lowerBound), channel \(channel)")
                XCTAssertEqual(fault.knownToneGapWindowCount(channel: 1 - channel), 0,
                               "Do not report the unaffected channel as a dropout")
                XCTAssertEqual(fault.knownToneGapWindowCount(channel: channel, dropping: missingFrames.upperBound), 0,
                               "An explicitly excluded startup segment must stay excluded")
            }
        }
    }

    @MainActor
    private func render(_ signal: QualitySignal, settings: MobileEQSettings, frames: Int,
                        pattern: [AVAudioFrameCount]) async throws -> QualityCapture {
        let effect = try await installedEffect()
        settings.apply(to: try XCTUnwrap(effect.auAudioUnit.parameterTree))
        let stream = try QualityRenderStream(effect: effect, signal: signal)
        defer { stream.close() }
        return try stream.capture(frames: frames, blockPattern: pattern)
    }

    @MainActor
    private func installedEffect() async throws -> AVAudioUnit {
        let components = AVAudioUnitComponentManager.shared().components(matching: MobileEQ.component)
        XCTAssertEqual(components.count, 1, "Install the app/extension before running the hosted regression suite")
        return try await AVAudioUnit.instantiate(with: MobileEQ.component, options: .loadOutOfProcess)
    }

    private func record(_ label: String, capture: QualityCapture, comparison: QualityComparison? = nil) {
        let text = """
        \(label)
        sampleRate=\(capture.sampleRate), channels=\(capture.samples.count), frames=\(capture.samples.first?.count ?? 0)
        nonfinite=\(capture.nonFiniteSamples), samplePeak=\(capture.peak), offlineContextRetries=\(capture.offlineContextRetries)
        \(comparison?.description ?? "No unity-reference comparison; fixture has intentional filtering")
        Offline installed-AUv3 render only. Physical Bluetooth and callback-deadline evidence are separate.
        """
        let attachment = XCTAttachment(string: text)
        attachment.name = label
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
