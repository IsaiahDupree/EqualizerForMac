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
        #expect(store.totalCount == 8851)
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
        // The original AutoEq catalog uses 10 filters; the supplemental Pro 3 preset uses six.
        let results = store.search("", limit: 400)
        #expect(results.count == 400)
        #expect(results.allSatisfy { $0.bands().count == 10 })
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
