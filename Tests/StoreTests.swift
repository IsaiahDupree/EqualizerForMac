import Foundation
import Testing
@testable import SonanceEQ

@MainActor
@Suite struct PresetStoreTests {
    let store = PresetStore.shared

    @Test func databaseIsAvailable() {
        #expect(store.isAvailable)
    }

    @Test func totalCountMatchesBuild() {
        #expect(store.totalCount == 8862)
    }

    @Test(arguments: ["HD 600", "AirPods", "Moondrop", "Sennheiser", "Sony", "Bose", "600", "Pro"])
    func searchFindsResults(_ term: String) {
        #expect(!store.search(term).isEmpty)
    }

    @Test func categoriesIncludeKnownFormFactors() {
        let cats = store.categories()
        #expect(cats.contains("in-ear") && cats.contains("over-ear"))
    }

    @Test(arguments: ["in-ear", "over-ear", "earbud"])
    func categoryFilterIsHonored(_ category: String) {
        let results = store.search("", category: category, limit: 40)
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.category == category })
    }

    @Test func searchedPresetsAllParse() {
        let results = store.search("Sennheiser", limit: 60)
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { !$0.bands().isEmpty })
    }

    @Test func limitIsRespected() {
        #expect(store.search("", limit: 25).count <= 25)
    }

    @Test func nonsenseTermReturnsEmpty() {
        #expect(store.search("zzqqxx_no_such_headphone").isEmpty)
    }

    @Test func everyHeadphonePresetHasTenFilters() {
        // Retain the original 400-correction check. Supplemental authors use variable band counts
        // and are checked against their exact published input below.
        let results = Array(store.search("", limit: 500).filter {
            $0.dataLicense != "CC BY-SA 4.0" && $0.model != "Apple AirPods Pro 3"
        }.prefix(400))
        #expect(results.count == 400)
        #expect(results.allSatisfy { $0.bands().count == 10 })
    }

    @Test(arguments: ["Beats by Dre", "Beats by Dr. Dre", "  BEATS BY DRE  "])
    func beatsBrandAliasesFindTheCompleteLibrary(_ term: String) {
        let expected = store.search("Beats", limit: 100)
        let actual = store.search(term, limit: 100)
        #expect(expected.count == 55)
        #expect(actual.map(\.id) == expected.map(\.id))
        #expect(actual.allSatisfy { $0.brand == "Beats" })
    }

    @Test(arguments: ["Solo3", "Solo 3", "Beats by Dre Solo 3", "solo-3"])
    func spacedGenerationNamesFindTheSamePresets(_ term: String) {
        #expect(store.search(term).map(\.id) == store.search("Beats Solo3").map(\.id))
    }

    @Test func plusModelsAndEarphonesKeepTheirIdentity() {
        let plus = store.search("Beats Studio Buds Plus")
        #expect(plus.count == 3)
        #expect(plus.map(\.id) == store.search("Beats Studio Buds+").map(\.id))
        #expect(plus.allSatisfy { $0.model.contains("+") })
        #expect(!store.search("Powerbeats 2", category: "in-ear").isEmpty)
        #expect(store.search("Powerbeats 2", category: "over-ear").isEmpty)
        #expect(store.search("AirPods 4").contains { $0.model == "Apple AirPods 4 (transparency)" })
        #expect(store.search("Powerbeats 4").allSatisfy { !$0.model.contains("Beats Beats") })
    }

    @Test(arguments: ["AirPods Max 2", "AirPods 5", "Powerbeats Fit", "Beats 360", "Solo 2 Wireless"])
    func anUnavailableGenerationDoesNotLoadAnotherModelsCurve(_ term: String) {
        #expect(store.search(term).isEmpty)
    }

    @Test(arguments: ["%", "_", "' OR 1=1 --", "\\"])
    func specialSearchCharactersAreLiteral(_ term: String) {
        #expect(store.search(term).isEmpty)
    }

    @Test func nonpositiveLimitsReturnNothing() {
        #expect(store.search("Beats", limit: 0).isEmpty)
        #expect(store.search("Beats", limit: -1).isEmpty)
    }

    @Test func publishedOPRADataLoadsWithItsAttributionAndExactFilters() throws {
        let entries = try publishedOPRAEntries()
        #expect(entries.count == 11)
        #expect(Bundle.main.url(forResource: "OPRA-LICENSE", withExtension: "txt") != nil)
        #expect(Bundle.main.url(forResource: "OPRA-logo", withExtension: "png") != nil)
        let types: [String: FilterType] = ["peak_dip": .peaking, "low_shelf": .lowShelf, "high_shelf": .highShelf]
        for entry in entries {
            let preset = try #require(store.search(entry.model).first { $0.sourceURL?.absoluteString == entry.sourceURL })
            #expect(preset.dataLicense == "CC BY-SA 4.0")
            #expect(preset.source == "\(entry.data.author) · \(entry.data.details) · OPRA")
            #expect(preset.preampDb == entry.preampDB)
            #expect(preset.preampDb <= entry.data.parameters.gainDB)
            let bands = preset.bands()
            #expect(bands.count == entry.data.parameters.bands.count)
            for (actual, expected) in zip(bands, entry.data.parameters.bands) {
                #expect(actual.frequency == expected.frequency && actual.gain == expected.gainDB)
                #expect(actual.q == expected.q && actual.type == types[expected.type] && actual.enabled)
            }
            let app = AppState()
            app.applyAutoEq(preset)
            #expect(app.bands.count == bands.count && app.preampDb == preset.preampDb)
            #expect(app.activePresetName == preset.displayName)
        }
    }

    @Test(arguments: [44_100.0, 48_000.0, 96_000.0, 192_000.0])
    func additionalBeatsResponsesAreStableWithPreampHeadroom(_ rate: Double) throws {
        let presets = store.search("Beats", limit: 100).filter { $0.dataLicense == "CC BY-SA 4.0" }
        #expect(presets.count == 11)
        for preset in presets {
            let bands = preset.bands()
            let curve = FrequencyResponse.curve(bands: bands, sampleRate: rate, points: 8192)
            #expect(curve.allSatisfy { $0.db.isFinite })
            #expect(curve.allSatisfy { $0.db + Double(preset.preampDb) <= 0 }, "\(preset.displayName) @ \(rate)")
            #expect(bands.flatMap { FilterDesigner.sections(for: $0, sampleRate: rate) }
                .allSatisfy { biquadStable($0) })
        }
    }

    @Test(arguments: ["AirPods Pro 3", "airpods pro 3", "  AirPods Pro 3  "])
    func airPodsPro3LoadsPublishedSixBandPreset(_ term: String) throws {
        let results = store.search(term, category: "in-ear")
        #expect(results.count == 1)
        let preset = try #require(results.first)
        #expect(preset.model == "Apple AirPods Pro 3")
        #expect(preset.brand == "Apple")
        #expect(preset.source == "Songbird · JM-1 (-10 dB tilt)")
        #expect(preset.preampDb == -3.9)
        let bands = preset.bands()
        #expect(bands.count == 6)
        // Values from the pinned MIT-licensed source, not a Pro 2 alias or generated tuning.
        #expect(bands.map(\.frequency) == [40, 151, 3417, 4305, 5747, 7671])
        #expect(bands.map(\.gain) == [-2.3, 3.7, 3.9, 1.5, -6.4, -2.9])
        #expect(bands.map(\.q) == [0.70, 1.41, 3, 2, 3, 1.41])
        #expect(bands.allSatisfy { $0.type == .peaking && $0.enabled })
        #expect(store.search(term, category: "over-ear").isEmpty)
        #expect(Bundle.main.url(forResource: "openEq-LICENSE", withExtension: "txt") != nil)
    }

    @Test(arguments: [44_100.0, 48_000.0, 96_000.0, 192_000.0])
    func airPodsPro3ResponseIsFiniteWithPreampHeadroom(_ rate: Double) throws {
        let preset = try #require(store.search("AirPods Pro 3").first)
        let bands = preset.bands()
        let curve = FrequencyResponse.curve(bands: bands, sampleRate: rate, points: 4096)
        #expect(curve.allSatisfy { $0.db.isFinite })
        #expect(curve.allSatisfy { $0.db + Double(preset.preampDb) <= 0 })
        #expect(bands.flatMap { FilterDesigner.sections(for: $0, sampleRate: rate) }
            .allSatisfy { biquadStable($0) })
    }

    @Test func airPodsPro3AppliesThroughShippingAppState() throws {
        let preset = try #require(store.search("AirPods Pro 3").first)
        let app = AppState()
        app.applyAutoEq(preset)
        #expect(app.bands.count == 6)
        #expect(app.bands.map(\.frequency) == preset.bands().map(\.frequency))
        #expect(app.preampDb == preset.preampDb)
        #expect(app.activePresetName == preset.displayName)
    }

    @Test func shareablePro3PresetDecodesWithShippingImporter() throws {
        let url = try #require(Bundle.main.url(forResource: "Apple-AirPods-Pro-3.sonanceeq", withExtension: "json"))
        let file = try JSONDecoder().decode(PresetFile.self, from: Data(contentsOf: url))
        let bundled = try #require(store.search("AirPods Pro 3").first)
        #expect(file.app == "SonanceEQ" && file.version == 1)
        #expect(file.preampDb == bundled.preampDb)
        let imported = file.eqBands()
        #expect(imported.count == 6)
        for (actual, expected) in zip(imported, bundled.bands()) {
            #expect(actual.frequency == expected.frequency && actual.gain == expected.gain)
            #expect(actual.q == expected.q && actual.type == expected.type)
            #expect(actual.enabled == expected.enabled && actual.slopeDbPerOct == expected.slopeDbPerOct)
        }
    }
}

private func publishedOPRAEntries() throws -> [PublishedOPRAEntry] {
    let url = try #require(Bundle.main.url(forResource: "OPRA-Beats", withExtension: "json"))
    struct Document: Decodable { let entries: [PublishedOPRAEntry] }
    return try JSONDecoder().decode(Document.self, from: Data(contentsOf: url)).entries
}

private struct PublishedOPRAEntry: Decodable {
    let model: String
    let sourceURL: String
    let preampDB: Float
    let data: PublishedOPRAData
    enum CodingKeys: String, CodingKey {
        case model, data
        case sourceURL = "source_url"
        case preampDB = "preamp_db"
    }
}

private struct PublishedOPRAData: Decodable {
    let author: String
    let details: String
    let parameters: PublishedOPRAParameters
}

private struct PublishedOPRAParameters: Decodable {
    let gainDB: Float
    let bands: [PublishedOPRABand]
    enum CodingKeys: String, CodingKey { case bands; case gainDB = "gain_db" }
}

private struct PublishedOPRABand: Decodable {
    let type: String
    let frequency: Double
    let gainDB: Float
    let q: Double
    enum CodingKeys: String, CodingKey { case type, frequency, q; case gainDB = "gain_db" }
}
