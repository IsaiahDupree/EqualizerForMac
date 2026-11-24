import XCTest
@testable import SonanceEQiOS

final class PresetLibraryTests: XCTestCase {
    func testPresetRoundTripPreservesIndependentMidSideCurves() throws {
        var settings = MobileEQSettings(bands: [EQBand(frequency: 800, gain: 3, q: 1.2)])
        settings.sideBands = [EQBand(frequency: 2_400, gain: -5, q: 0.8)]
        settings.midSideEnabled = true
        settings.linearPhaseEnabled = true
        let file = PresetFile(name: "Independent curves", preampDb: -2, bands: settings.bands,
                              sideBands: settings.sideBands, midSideEnabled: settings.midSideEnabled,
                              linearPhaseEnabled: settings.linearPhaseEnabled)
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(PresetFile.self, from: data)
        let restored = try MobileEQSettings(preset: decoded)
        XCTAssertEqual(restored.bands.map(\.frequency), [800])
        XCTAssertEqual(restored.sideBands.map(\.frequency), [2_400])
        XCTAssertEqual(restored.sideBands.map(\.gain), [-5])
        XCTAssertTrue(restored.midSideEnabled)
        XCTAssertTrue(restored.linearPhaseEnabled)
    }

    @MainActor
    func testImportsAutoEqTextWithPreampShelvesAndDisabledBands() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = directory.appending(path: "Headphones ParametricEQ.txt")
        let unsupported = directory.appending(path: "Stereo.txt")
        let filters = """
            # Headphone correction
            Preamp: -4.5 dB
            Filter 1: ON LSC Fc 105 Hz Gain 3.2 dB Q 0.71
            Filter 2: OFF PK Fc 400 Hz Gain 2.0 dB Q 1.00
            Filter 3: ON HSC Fc 9000 Hz Gain -2.3 dB Q 0.70
            """
        try Data(filters.utf8).write(to: profile)
        try Data((filters + "\nChannel: L").utf8).write(to: unsupported)

        let result = PresetImport.read([profile, unsupported])
        XCTAssertEqual(result.files.map(\.name), ["Headphones ParametricEQ"])
        XCTAssertEqual(result.problems.count, 1)
        XCTAssertTrue(try XCTUnwrap(result.problems.first).contains("Line 6"))

        let storage = directory.appending(path: "presets.json")
        XCTAssertEqual(try PresetLibrary(url: storage).append(result.files), 1)
        let preset = try XCTUnwrap(PresetLibrary(url: storage).entries.first)
        let settings = try MobileEQSettings(preset: preset.file)
        XCTAssertEqual(settings.preamp, -4.5)
        XCTAssertEqual(settings.bands.map(\.type), [.lowShelf, .peaking, .highShelf])
        XCTAssertEqual(settings.bands.map(\.frequency), [105, 400, 9000])
        XCTAssertEqual(settings.bands.map(\.gain), [3.2, 2, -2.3])
        XCTAssertEqual(settings.bands.map(\.q), [0.71, 1, 0.70])
        XCTAssertEqual(settings.bands.map(\.enabled), [true, false, true])
    }

    @MainActor
    func testLibrarySavesCurrentCurveAndBulkImportsMacFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appending(path: "presets.json")
        let preset = PresetFile(name: "Desk", preampDb: -6, bands: [
            EQBand(frequency: 140, gain: 4, q: 0.7, type: .lowShelf),
            EQBand(frequency: 45, gain: 0, q: 0.7, type: .highPass, slopeDbPerOct: 24),
        ])
        let encoder = PresetLibrary.encoder()
        let macFile = directory.appending(path: "Desk.sonanceeq.json")
        let collection = directory.appending(path: "Sonance Presets.json")
        let broken = directory.appending(path: "wrong.json")
        try encoder.encode(preset).write(to: macFile)
        var alternate = preset
        alternate.preampDb = -11
        try encoder.encode(PresetCollection(presets: [preset, alternate])).write(to: collection)
        try Data("{}".utf8).write(to: broken)

        let library = PresetLibrary(url: storage)
        var current = MobileEQSettings()
        current.bands[7].gain = 4.5
        try library.save(current, name: "Travel")
        current.bands[7].gain = 0
        let batch = PresetImport.read([macFile, collection, broken])
        XCTAssertEqual(batch.files.count, 3)
        XCTAssertEqual(batch.problems.count, 1)
        XCTAssertEqual(try library.append(batch.files), 2)
        XCTAssertEqual(try library.append(batch.files), 0)

        let reloaded = PresetLibrary(url: storage)
        XCTAssertEqual(reloaded.entries.map(\.file.name), ["Travel", "Desk", "Desk (2)"])
        XCTAssertEqual(reloaded.entries[0].file.bands[7].gain, 4.5)
        let settings = try MobileEQSettings(preset: reloaded.entries[1].file)
        XCTAssertEqual(settings.preamp, -6)
        XCTAssertEqual(settings.bands[0].type, .lowShelf)
        XCTAssertEqual(settings.bands[1].slopeDbPerOct, 24)
        XCTAssertEqual(settings.bands.count, 2)
        XCTAssertTrue(settings.bands.allSatisfy(\.enabled))
    }
}
