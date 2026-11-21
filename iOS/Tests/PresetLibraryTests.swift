import XCTest
@testable import SonanceEQiOS

final class PresetLibraryTests: XCTestCase {
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
        XCTAssertTrue(settings.bands.dropFirst(2).allSatisfy { !$0.enabled })
    }
}
