import XCTest
@testable import SonanceEQiOS

final class AutoEqCatalogTests: XCTestCase {
    @MainActor
    func testBundledCatalogSearchAndCorrectionConversion() throws {
        let catalog = AutoEqCatalog.shared
        XCTAssertTrue(catalog.isAvailable, "The offline headphone catalog must be bundled in the app.")
        XCTAssertGreaterThan(catalog.totalCount, 8_000)
        XCTAssertTrue(catalog.categories().contains("over-ear"))

        let results = catalog.search("AirPods Pro 3", limit: 20)
        let preset = try XCTUnwrap(results.first { $0.model.localizedCaseInsensitiveContains("AirPods Pro 3") })
        let settings = try preset.settings()
        XCTAssertFalse(settings.bands.isEmpty)
        XCTAssertLessThan(settings.preamp, 0)
        XCTAssertTrue(settings.isValid)
        XCTAssertEqual(settings.bands.count, 6)
        XCTAssertEqual(settings.bypassed, false)

        let outputCorrection = try OutputCorrection(preset: preset)
        XCTAssertEqual(outputCorrection.name, preset.displayName)
        XCTAssertEqual(outputCorrection.settings, settings)
        XCTAssertTrue(outputCorrection.isValid)
    }

    @MainActor
    func testCatalogEscapesSearchWildcardsAndFiltersByCategory() {
        let catalog = AutoEqCatalog.shared
        let literalWildcard = catalog.search("%_\\", limit: 20)
        XCTAssertTrue(literalWildcard.isEmpty)
        XCTAssertTrue(catalog.search("AirPods%", limit: 20).isEmpty)

        let inEar = catalog.search("AirPods", category: "in-ear", limit: 50)
        XCTAssertFalse(inEar.isEmpty)
        XCTAssertTrue(inEar.allSatisfy { $0.category == "in-ear" })
    }

    @MainActor
    func testSelectingCatalogCorrectionUpdatesAndPersistsMainEQ() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EqualizerStore(file: directory.appending(path: "session.json"), legacyDefaults: .standard)
        let session = EqualizerSession(store: store)
        let preset = try XCTUnwrap(AutoEqCatalog.shared.search("AirPods Pro 3", limit: 20).first)

        try session.applyHeadphoneCorrection(preset)

        let expected = try preset.settings()
        XCTAssertEqual(session.snapshot.settings, expected)
        XCTAssertEqual(session.player.settings, expected)
        XCTAssertEqual(session.snapshot.selectedBand, 0)
        XCTAssertEqual(try store.load().settings, expected)
    }
}
