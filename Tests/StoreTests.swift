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
        #expect(store.totalCount == 8850)
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
        // AutoEq parametric presets are all 10 filters; sample a large slice.
        let results = store.search("", limit: 400)
        #expect(results.count == 400)
        #expect(results.allSatisfy { $0.bands().count == 10 })
    }
}
