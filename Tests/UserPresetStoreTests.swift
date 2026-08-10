import Foundation
import Testing
@testable import SonanceEQ

@MainActor
@Suite struct UserPresetStoreTests {
    private func fresh() -> UserPresetStore {
        UserPresetStore(defaults: UserDefaults(suiteName: "test.userpresets.\(UUID().uuidString)")!)
    }

    private var someBands: [EQBand] { [EQBand(frequency: 1000, gain: 3, q: 1, type: .peaking)] }

    @Test func startsEmpty() {
        #expect(fresh().presets.isEmpty)
    }

    @Test func saveAppendsAndReturnsPreset() {
        let store = fresh()
        let saved = store.save(name: "My Curve", preampDb: -2, bands: someBands)
        #expect(saved != nil)
        #expect(store.presets.count == 1)
        #expect(store.presets[0].name == "My Curve")
        #expect(store.presets[0].preampDb == -2)
    }

    @Test func saveTrimsWhitespace() {
        let store = fresh()
        store.save(name: "  Padded  ", preampDb: 0, bands: someBands)
        #expect(store.presets.first?.name == "Padded")
    }

    @Test func saveRejectsBlankName() {
        let store = fresh()
        #expect(store.save(name: "   ", preampDb: 0, bands: someBands) == nil)
        #expect(store.presets.isEmpty)
    }

    @Test func saveRejectsEmptyBands() {
        let store = fresh()
        #expect(store.save(name: "Empty", preampDb: 0, bands: []) == nil)
        #expect(store.presets.isEmpty)
    }

    @Test func deleteRemovesPreset() {
        let store = fresh()
        let preset = store.save(name: "Delete Me", preampDb: 0, bands: someBands)!
        store.delete(preset.id)
        #expect(store.presets.isEmpty)
    }

    @Test func renameUpdatesName() {
        let store = fresh()
        let preset = store.save(name: "Old Name", preampDb: 0, bands: someBands)!
        store.rename(preset.id, to: "New Name")
        #expect(store.presets.first?.name == "New Name")
    }

    @Test func renameIgnoresBlankName() {
        let store = fresh()
        let preset = store.save(name: "Keep Me", preampDb: 0, bands: someBands)!
        store.rename(preset.id, to: "   ")
        #expect(store.presets.first?.name == "Keep Me")
    }

    @Test func persistsAcrossInstances() {
        let suite = UserDefaults(suiteName: "test.userpresets.\(UUID().uuidString)")!
        let bands = someBands
        UserPresetStore(defaults: suite).save(name: "Survives", preampDb: 1.5, bands: bands)
        let reloaded = UserPresetStore(defaults: suite)
        #expect(reloaded.presets.count == 1)
        #expect(reloaded.presets[0].name == "Survives")
        #expect(reloaded.presets[0].bands == bands)
    }
}
