import AudioToolbox
import AVFAudio
import AVFoundation
import CoreAudioKit
import XCTest
@testable import SonanceEQiOS

final class AudioUnitIntegrationTests: XCTestCase {
    @MainActor
    func testInstalledEffectProcessesStereoAndBypassesDuringPlayback() async throws {
        let effect = try await installedEffect()
        let tree = try XCTUnwrap(effect.auAudioUnit.parameterTree)
        XCTAssertEqual(tree.allParameters.count, 10 + 2 * MobileEQ.maximumBandCount * MobileEQ.Control.allCases.count)
        let gain = try XCTUnwrap(tree.parameter(withAddress: MobileEQ.address(.gain, band: 5)))
        XCTAssertEqual(gain.address, 18, "Existing host sessions use the original parameter addresses")
        XCTAssertEqual(MobileEQ.address(.type, band: 0), 32)
        XCTAssertEqual(MobileEQ.address(.enabled, band: 9), 61)
        XCTAssertEqual(MobileEQ.midSideEnabledAddress, 195)
        XCTAssertEqual(MobileEQ.sideAddress(.frequency, band: 0), 196)
        XCTAssertEqual(MobileEQ.sideBandCountAddress, 388)
        XCTAssertEqual(MobileEQ.linearPhaseEnabledAddress, 389)
        XCTAssertEqual(MobileEQ.renderBlocksAddress, 390)
        XCTAssertEqual(MobileEQ.lastDeadlineMicrosecondsAddress, 393)
        let preamp = try XCTUnwrap(tree.parameter(withAddress: MobileEQ.preampAddress))
        gain.value = 9
        preamp.value = -3

        let stream = try RenderStream(effect: effect, frequencies: [1_000, 6_000])
        let wet = try stream.measure()
        XCTAssertEqual(wet[0], 6, accuracy: 0.25)
        XCTAssertEqual(wet[1], -2.9, accuracy: 0.35)
        let metrics = await renderMetricsAfterOutOfProcessSync(tree)
        XCTAssertGreaterThan(metrics?.completedBlocks ?? 0, 0)
        XCTAssertGreaterThan(metrics?.maximumProcessingMicroseconds ?? 0, 0)
        XCTAssertGreaterThan(metrics?.lastDeadlineMicroseconds ?? 0, 0)

        effect.auAudioUnit.shouldBypassEffect = true
        let dry = try stream.measure()
        XCTAssertEqual(dry[0], 0, accuracy: 0.08)
        XCTAssertEqual(dry[1], 0, accuracy: 0.08)

        effect.auAudioUnit.shouldBypassEffect = false
        gain.value = -6
        let cut = try stream.measure()
        XCTAssertEqual(cut[0], -9, accuracy: 0.25)
    }

    @MainActor
    func testMidSideCurvesRestoreThroughHostParameterState() async throws {
        let effect = try await installedEffect()
        let tree = try XCTUnwrap(effect.auAudioUnit.parameterTree)
        var settings = MobileEQSettings(bands: [
            EQBand(frequency: 997, gain: 6, q: 1, type: .peaking),
        ], preamp: -2)
        settings.sideBands = [EQBand(frequency: 997, gain: -4, q: 1, type: .peaking)]
        settings.midSideEnabled = true
        settings.linearPhaseEnabled = true
        settings.apply(to: tree)
        XCTAssertEqual(tree.parameter(withAddress: MobileEQ.midSideEnabledAddress)?.value, 1)
        XCTAssertEqual(tree.parameter(withAddress: MobileEQ.sideBandCountAddress)?.value, 1)
        XCTAssertEqual(tree.parameter(withAddress: MobileEQ.sideAddress(.gain, band: 0))?.value, -4)
        XCTAssertEqual(tree.parameter(withAddress: MobileEQ.linearPhaseEnabledAddress)?.value, 1)

        let restored = try await installedEffect()
        restored.auAudioUnit.fullState = try XCTUnwrap(effect.auAudioUnit.fullState)
        let restoredTree = try XCTUnwrap(restored.auAudioUnit.parameterTree)
        XCTAssertEqual(restoredTree.parameter(withAddress: MobileEQ.midSideEnabledAddress)?.value, 1)
        XCTAssertEqual(restoredTree.parameter(withAddress: MobileEQ.sideBandCountAddress)?.value, 1)
        XCTAssertEqual(restoredTree.parameter(withAddress: MobileEQ.sideAddress(.gain, band: 0))?.value, -4)
        XCTAssertEqual(restoredTree.parameter(withAddress: MobileEQ.linearPhaseEnabledAddress)?.value, 1)
    }

    @MainActor
    func testAddingAndRemovingBandsChangesTheRenderedAudioAndRestoresInAHost() async throws {
        let effect = try await installedEffect()
        let tree = try XCTUnwrap(effect.auAudioUnit.parameterTree)
        let count = try XCTUnwrap(tree.parameter(withAddress: MobileEQ.bandCountAddress))
        XCTAssertEqual(count.value, Float(MobileEQ.initialBandCount))
        var edited = MobileEQSettings()
        edited.bands[5].gain = -2
        edited.apply(to: tree)
        let stream = try RenderStream(effect: effect, frequencies: [1_000])
        XCTAssertEqual(try stream.measure()[0], -2, accuracy: 0.25)

        let original = edited
        var newBand = MobileEQ.newBand()
        newBand.gain = 8
        edited.bands.append(newBand)
        edited.apply(to: tree, changedFrom: original)
        XCTAssertEqual(count.value, Float(MobileEQ.initialBandCount + 1))
        XCTAssertEqual(try stream.measure()[0], 6, accuracy: 0.25)

        let restored = try await installedEffect()
        restored.auAudioUnit.fullState = try XCTUnwrap(effect.auAudioUnit.fullState)
        let restoredTree = try XCTUnwrap(restored.auAudioUnit.parameterTree)
        XCTAssertEqual(restoredTree.parameter(withAddress: MobileEQ.bandCountAddress)?.value, count.value)
        XCTAssertEqual(try RenderStream(effect: restored, frequencies: [1_000]).measure()[0], 6, accuracy: 0.25)

        original.apply(to: tree, changedFrom: edited)
        XCTAssertEqual(try stream.measure()[0], -2, accuracy: 0.25)

        var replacement = original
        replacement.bands.append(MobileEQ.newBand())
        replacement.apply(to: tree, changedFrom: original)
        XCTAssertEqual(try stream.measure()[0], -2, accuracy: 0.25)

        var empty = MobileEQSettings(bands: [], preamp: -3)
        empty.apply(to: tree, changedFrom: replacement)
        XCTAssertEqual(count.value, 0)
        XCTAssertEqual(try stream.measure()[0], -3, accuracy: 0.25)

        let reset = empty
        empty.bands = (0..<MobileEQ.maximumBandCount).map { _ in MobileEQ.newBand() }
        empty.bands[MobileEQ.maximumBandCount - 1].gain = 6
        empty.apply(to: tree, changedFrom: reset)
        XCTAssertEqual(count.value, Float(MobileEQ.maximumBandCount))
        XCTAssertEqual(try stream.measure()[0], 3, accuracy: 0.25)
    }

    @MainActor
    func testHostRestoresParameterStateAndRendersMono() async throws {
        let first = try await installedEffect()
        let tree = try XCTUnwrap(first.auAudioUnit.parameterTree)
        let center = MobileEQ.address(.frequency, band: 0)
        let gain = MobileEQ.address(.gain, band: 0)
        try XCTUnwrap(tree.parameter(withAddress: center)).value = 750
        try XCTUnwrap(tree.parameter(withAddress: gain)).value = 6

        let restored = try await installedEffect()
        restored.auAudioUnit.fullState = try XCTUnwrap(first.auAudioUnit.fullState)
        let restoredTree = try XCTUnwrap(restored.auAudioUnit.parameterTree)
        XCTAssertEqual(try XCTUnwrap(restoredTree.parameter(withAddress: center)).value, 750)
        XCTAssertEqual(try XCTUnwrap(restoredTree.parameter(withAddress: gain)).value, 6)
        let stream = try RenderStream(effect: restored, frequencies: [750])
        XCTAssertEqual(try stream.measure()[0], 6, accuracy: 0.25)
    }

    @MainActor
    func testMacFilterShapesRenderAndRestoreInAHost() async throws {
        let effect = try await installedEffect()
        let tree = try XCTUnwrap(effect.auAudioUnit.parameterTree)
        func parameter(_ control: MobileEQ.Control) throws -> AUParameter {
            try XCTUnwrap(tree.parameter(withAddress: MobileEQ.address(control, band: 0)))
        }
        try parameter(.type).value = Float(try XCTUnwrap(MobileEQ.filterTypes.firstIndex(of: .lowShelf)))
        try parameter(.frequency).value = 400
        try parameter(.gain).value = 8
        try parameter(.quality).value = 0.707
        let restored = try await installedEffect()
        restored.auAudioUnit.fullState = try XCTUnwrap(effect.auAudioUnit.fullState)
        let spectrum = try RenderStream(effect: restored, frequencies: [100, 3_000]).measure()
        XCTAssertEqual(spectrum[0], 8, accuracy: 0.3)
        XCTAssertEqual(spectrum[1], 0, accuracy: 0.15)

        let cut = try await installedEffect()
        let cutTree = try XCTUnwrap(cut.auAudioUnit.parameterTree)
        try XCTUnwrap(cutTree.parameter(withAddress: MobileEQ.address(.type, band: 0))).value =
            Float(try XCTUnwrap(MobileEQ.filterTypes.firstIndex(of: .highPass)))
        try XCTUnwrap(cutTree.parameter(withAddress: MobileEQ.address(.slope, band: 0))).value =
            Float(try XCTUnwrap(FilterDesigner.slopes.firstIndex(of: 24)))
        try XCTUnwrap(cutTree.parameter(withAddress: MobileEQ.address(.frequency, band: 0))).value = 400
        let response = try RenderStream(effect: cut, frequencies: [200, 3_000]).measure()
        XCTAssertEqual(response[0], -24, accuracy: 1)
        XCTAssertEqual(response[1], 0, accuracy: 0.12)
    }

    @MainActor
    func testBundledHeadphoneCorrectionAppliesToTheAudioUnitParameterTree() async throws {
        let preset = try XCTUnwrap(AutoEqCatalog.shared.search("AirPods Pro 3", limit: 20).first)
        let expected = try preset.settings()
        let effect = try await installedEffect()
        let tree = try XCTUnwrap(effect.auAudioUnit.parameterTree)

        expected.apply(to: tree)

        XCTAssertEqual(tree.parameter(withAddress: MobileEQ.bandCountAddress)?.value, Float(expected.bands.count))
        XCTAssertEqual(tree.parameter(withAddress: MobileEQ.preampAddress)?.value, expected.preamp)
        XCTAssertEqual(tree.parameter(withAddress: MobileEQ.bypassAddress)?.value, 0)
        for (index, band) in expected.bands.enumerated() {
            XCTAssertEqual(tree.parameter(withAddress: MobileEQ.address(.frequency, band: index))?.value, Float(band.frequency))
            XCTAssertEqual(tree.parameter(withAddress: MobileEQ.address(.gain, band: index))?.value, band.gain)
            XCTAssertEqual(tree.parameter(withAddress: MobileEQ.address(.quality, band: index))?.value, Float(band.q))
        }

        let rendered = try RenderStream(effect: effect, frequencies: [1_000, 4_000]).measure()
        XCTAssertEqual(rendered.count, 2)
        XCTAssertTrue(rendered.allSatisfy { $0.isFinite }, "A bundled correction must render finite output through the installed Audio Unit.")
    }

    @MainActor
    func testHostCanRequestSonanceEditor() async throws {
        let effect = try await installedEffect()
        XCTAssertTrue(effect.auAudioUnit.providesUserInterface)
        let editor = await effect.auAudioUnit.requestViewController()
        XCTAssertNotNil(editor)
    }

    @MainActor
    func testFloatingCurveVideoRendersTheFilterAndPlaybackProgress() throws {
        let renderer = CurveVideoRenderer()
        var settings = MobileEQSettings()
        func render(progress: Double) throws -> Data {
            let frame = CurveVideoFrame(title: "Sonance", settings: settings, sampleRate: 48_000, progress: progress)
            let sample = try XCTUnwrap(renderer.render(frame))
            XCTAssertTrue(CMSampleBufferDataIsReady(sample))
            let image = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            XCTAssertEqual(CVPixelBufferGetWidth(image), 480)
            XCTAssertEqual(CVPixelBufferGetHeight(image), 270)
            CVPixelBufferLockBaseAddress(image, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
            let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(image))
            return Data(bytes: address, count: CVPixelBufferGetBytesPerRow(image) * CVPixelBufferGetHeight(image))
        }
        let flat = try render(progress: 0)
        settings.bands[5].gain = 10
        let boosted = try render(progress: 0)
        XCTAssertNotEqual(flat, boosted)
        XCTAssertNotEqual(boosted, try render(progress: 0.5))
    }

    @MainActor
    func testAppPlaysASelectedAudioFileThroughItsEmbeddedEffect() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let buffer = try makeTone(frequencies: [1_000], frames: 144_000)
        do {
            let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
            try file.write(from: buffer)
        }

        let player = PreviewPlayer()
        defer { player.stop() }
        player.select(url)
        var boosted = MobileEQSettings()
        boosted.bands[5].gain = 6
        player.apply(boosted)
        XCTAssertEqual(player.fileName, url.lastPathComponent)
        await player.play()
        XCTAssertEqual(player.state, .playing, player.error ?? "")
        XCTAssertNotNil(player.outputName)
        var measured: AudioAnalysisFrame?
        for _ in 0..<22 {
            if let frame = player.readAnalysis(), frame.dominantFrequency != nil {
                measured = frame
                break
            }
            try await Task.sleep(for: .milliseconds(70))
        }
        let frame = try XCTUnwrap(measured, "The visualizer should receive actual audio from the EQ output")
        XCTAssertEqual(try XCTUnwrap(frame.dominantFrequency), 1_000, accuracy: 25)
        XCTAssertEqual(frame.left.peak, -12.1, accuracy: 0.6)
        XCTAssertNil(frame.right)
        try await assertLiveRenderMetItsDeadlines(player)
        player.pause()
        XCTAssertEqual(player.state, .paused)
        await player.play()
        XCTAssertEqual(player.state, .playing, player.error ?? "")
        player.stop()
        XCTAssertEqual(player.state, .idle)
        XCTAssertNil(player.outputName)
    }

    @MainActor
    func testPlaybackAppliesSavedCorrectionAfterEQAndBypassesItIndependently() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Tone.wav")
        let buffer = try makeTone(frequencies: [1_000], frames: 384_000)
        do {
            let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
            try file.write(from: buffer)
        }
        let store = EqualizerStore(file: directory.appending(path: "session.json"), legacyDefaults: .standard)
        let session = EqualizerSession(store: store)
        let player = session.player
        defer { player.stop() }
        session.updateEQ { $0.bands[5].gain = 6 }
        player.select(url)
        await player.play()
        XCTAssertEqual(player.state, .playing, player.error ?? "")
        let output = try XCTUnwrap(player.currentOutput)

        func expectPeak(_ expected: Float, file: StaticString = #filePath, line: UInt = #line) async throws {
            var peak: Float?
            for _ in 0..<25 {
                peak = player.readAnalysis()?.left.peak ?? peak
                if let peak, abs(peak - expected) <= 0.6 { return }
                try await Task.sleep(for: .milliseconds(60))
            }
            XCTAssertEqual(try XCTUnwrap(peak), expected, accuracy: 0.6, file: file, line: line)
        }

        try await expectPeak(-12.1)
        let preset = SavedPreset(file: PresetFile(name: "Speaker", preampDb: -7, bands: [
            EQBand(frequency: 1_000, gain: 2, q: 1, type: .peaking),
        ]))
        var correction = try OutputCorrection(preset: preset)
        XCTAssertTrue(session.setCorrection(correction, for: output))
        try await expectPeak(-17.1)
        XCTAssertEqual(EqualizerSession(store: store).correction(for: output), correction)

        session.updateEQ { $0.bypassed = true }
        try await expectPeak(-23.1)
        correction.enabled = false
        XCTAssertTrue(session.setCorrection(correction, for: output))
        try await expectPeak(-18.1)
        XCTAssertEqual(EqualizerSession(store: store).correction(for: output), correction)
        try await assertLiveRenderMetItsDeadlines(player)
    }

    @MainActor
    func testLiveFullBandMidSideFIRLoadMeetsRenderDeadlines() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let buffer = try makeTone(frequencies: [500, 1_200], frames: 384_000)
        do {
            let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
            try file.write(from: buffer)
        }

        func bands(gainSign: Float) -> [EQBand] {
            (0..<MobileEQ.maximumBandCount).map { index in
                let fraction = Double(index) / Double(MobileEQ.maximumBandCount - 1)
                let frequency = 35 * pow(16_000 / 35, fraction)
                let gain = index.isMultiple(of: 2) ? gainSign * 0.5 : -gainSign * 0.5
                return EQBand(frequency: frequency, gain: gain, q: 0.707, type: .peaking)
            }
        }

        var settings = MobileEQSettings(bands: bands(gainSign: 1), preamp: -18)
        settings.sideBands = bands(gainSign: -1)
        settings.midSideEnabled = true
        settings.linearPhaseEnabled = true
        XCTAssertTrue(settings.isValid)

        let player = PreviewPlayer()
        defer { player.stop() }
        player.select(url)
        player.apply(settings)
        await player.play()
        XCTAssertEqual(player.state, .playing, player.error ?? "")

        var frames: [AudioAnalysisFrame] = []
        for _ in 0..<24 {
            if let frame = player.readAnalysis() { frames.append(frame) }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertGreaterThan(frames.count, 5, "Full-load playback should keep producing analysis frames")
        XCTAssertTrue(frames.contains { $0.left.peak.isFinite && $0.right?.peak.isFinite == true })
        try await assertLiveRenderMetItsDeadlines(player)
    }

    private func installedEffect() async throws -> AVAudioUnit {
        let manager = AVAudioUnitComponentManager.shared()
        let componentCount = manager.components(matching: MobileEQ.component).count
        do {
            return try await AVAudioUnit.instantiate(with: MobileEQ.component, options: .loadOutOfProcess)
        } catch {
            throw NSError(domain: "SonanceEQ.AudioUnitIntegrationTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Sonance AUv3 instantiation failed (component catalog matches: \(componentCount)): \(error.localizedDescription)"])
        }
    }

    @MainActor
    private func renderMetricsAfterOutOfProcessSync(_ tree: AUParameterTree) async -> AudioRenderMetrics? {
        // AVAudioUnit.instantiate(.loadOutOfProcess) proxies render telemetry
        // across the extension boundary; allow its read-only parameter values
        // to catch up after the offline engine has completed its render calls.
        for _ in 0..<50 {
            let metrics = AudioRenderMetrics(parameterTree: tree)
            if (metrics?.completedBlocks ?? 0) > 0,
               (metrics?.lastDeadlineMicroseconds ?? 0) > 0 {
                return metrics
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return AudioRenderMetrics(parameterTree: tree)
    }

    @MainActor
    private func assertLiveRenderMetItsDeadlines(_ player: PreviewPlayer,
                                                file: StaticString = #filePath,
                                                line: UInt = #line) async throws {
        var metrics: AudioRenderMetrics?
        for _ in 0..<30 {
            metrics = player.readRenderMetrics()
            if (metrics?.completedBlocks ?? 0) > 0 { break }
            try await Task.sleep(for: .milliseconds(40))
        }
        let live = try XCTUnwrap(metrics, "Live Audio Unit render telemetry should be available", file: file, line: line)
        XCTAssertGreaterThan(live.completedBlocks, 0, file: file, line: line)
        XCTAssertEqual(live.deadlineMisses, 0, "Live rendering must not miss an audio buffer deadline", file: file, line: line)
    }
}
