import XCTest
@testable import SonanceEQiOS

final class EqualizerSessionTests: XCTestCase {
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
