import XCTest
@testable import SonanceEQiOS

final class EqualizerSessionTests: XCTestCase {
    func testLegacySettingsDecodeWithFlatSideCurveAndStereoModeOff() throws {
        let legacy = #"{"bands":[],"preamp":-3,"bypassed":false}"#
        let settings = try JSONDecoder().decode(MobileEQSettings.self, from: Data(legacy.utf8))
        XCTAssertTrue(settings.bands.isEmpty)
        XCTAssertEqual(settings.preamp, -3)
        XCTAssertFalse(settings.midSideEnabled)
        XCTAssertEqual(settings.sideBands, Presets.flat)
        XCTAssertTrue(settings.isValid)
    }

    @MainActor
    func testSpeechProfileIsAudibleEditableAndSurvivesRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let domain = "SonanceSpeechTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = EqualizerStore(file: directory.appending(path: "session.json"), legacyDefaults: defaults)
        let session = EqualizerSession(store: store)
        session.updateEQ { $0.bypassed = true }
        session.captureReference()
        session.auditionReference(true)
        session.applySpeechListening(.podcast)

        XCTAssertFalse(session.playingReference)
        XCTAssertFalse(session.snapshot.settings.bypassed)
        XCTAssertEqual(session.player.settings, session.snapshot.settings)
        XCTAssertEqual(session.snapshot.settings.preamp, -3)
        XCTAssertEqual(session.snapshot.settings.bands.count, 10)
        XCTAssertEqual(try store.load(), session.snapshot)
        session.updateEQ { $0.bands[0].gain = -6 }
        XCTAssertEqual(EqualizerSession(store: store).snapshot.settings.bands[0].gain, -6)
    }

    func testSpeechProfilesHaveValidCurvesWithReducedLowEnd() {
        for profile in SpeechListening.allCases {
            let settings = profile.settings
            XCTAssertTrue(settings.isValid, profile.title)
            let response = FrequencyResponse.curve(bands: settings.bands, sampleRate: 48_000,
                                                   points: 3, fMin: 62.5, fMax: 2_000)
            XCTAssertLessThan(response[0].db, response[2].db, profile.title)
            XCTAssertLessThan(settings.preamp, 0, profile.title)
        }
    }

    @MainActor
    func testAddedAndDeletedBandsPersistIncludingAnEmptyCurve() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EqualizerStore(file: directory.appending(path: "session.json"), legacyDefaults: .standard)
        let session = EqualizerSession(store: store)

        // A build 4 snapshot has the ten starting bands and an integer selection.
        try store.save(session.snapshot)
        let upgraded = EqualizerSession(store: store)
        XCTAssertEqual(upgraded.snapshot, session.snapshot)
        let band = MobileEQ.newBand()
        upgraded.updateEQ { $0.bands.append(band) }
        upgraded.selectBand(MobileEQ.initialBandCount)
        let extended = EqualizerSession(store: store)
        XCTAssertEqual(extended.snapshot.settings.bands.last, band)
        XCTAssertEqual(extended.snapshot.selectedBand, MobileEQ.initialBandCount)

        extended.updateEQ { $0.bands.removeAll() }
        let empty = EqualizerSession(store: store)
        XCTAssertTrue(empty.snapshot.settings.bands.isEmpty)
        XCTAssertNil(empty.snapshot.selectedBand)
        empty.updateEQ { $0.bands.append(MobileEQ.newBand()) }
        XCTAssertEqual(try store.load().selectedBand, 0)
    }

    @MainActor
    func testAuditioningAProtectsTheEditedCurveAndSavedSettings() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EqualizerStore(file: directory.appending(path: "session.json"), legacyDefaults: .standard)
        let session = EqualizerSession(store: store)
        session.updateEQ { $0.preamp = -2 }
        session.captureReference()
        session.updateEQ { $0.preamp = -8 }
        XCTAssertEqual(session.player.settings.preamp, -8)
        session.auditionReference(true)
        XCTAssertEqual(session.player.settings.preamp, -2)
        XCTAssertEqual(try store.load().settings.preamp, -8)
        session.auditionReference(false)
        XCTAssertEqual(session.player.settings.preamp, -8)
    }

    @MainActor
    func testExistingTuningSurvivesUpgradeAndACompletedEdit() throws {
        let location = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let domain = "SonanceEQSessionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: location)
        }
        let store = EqualizerStore(file: location.appending(path: "equalizer-session.json"), legacyDefaults: defaults)
        var previous = MobileEQSettings()
        previous.bands = Presets.vocal
        previous.preamp = -3
        previous.bypassed = true
        defaults.set(try JSONEncoder().encode(previous), forKey: EqualizerStore.legacyKey)

        let session = EqualizerSession(store: store)
        XCTAssertEqual(session.snapshot.settings, previous)
        session.selectBand(8)
        session.editingChanged(true)
        session.updateEQ { $0.bands[8].q = 3.5 }
        XCTAssertEqual(try store.load().settings, previous)
        session.editingChanged(false)

        let relaunched = EqualizerSession(store: store)
        XCTAssertEqual(relaunched.snapshot, session.snapshot)
        XCTAssertEqual(relaunched.snapshot.selectedBand, 8)
        XCTAssertEqual(relaunched.snapshot.settings.bands[8].q, 3.5)
        XCTAssertEqual(relaunched.snapshot.settings.preamp, -3)
        XCTAssertTrue(relaunched.snapshot.settings.bypassed)
    }

    @MainActor
    func testBackgroundCheckpointCapturesAnInProgressSliderEdit() throws {
        let location = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let domain = "SonanceEQSessionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: location)
        }
        let store = EqualizerStore(file: location.appending(path: "equalizer-session.json"), legacyDefaults: defaults)
        let session = EqualizerSession(store: store)
        session.editingChanged(true)
        session.updateEQ { $0.preamp = -7 }
        session.checkpointForBackground()
        XCTAssertEqual(try store.load().settings.preamp, -7)
        session.updateEQ { $0.bypassed = true }
        XCTAssertTrue(try store.load().settings.bypassed)
    }
}
