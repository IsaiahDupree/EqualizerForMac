import Foundation
import Testing
@testable import SonanceEQ

@Suite struct OutputPresetStoreTests {
    @Test func outputPresetsRemainIndependentAfterSavingAndRemoving() throws {
        let suite = "test.sonance.output-presets.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OutputPresetStore(defaults: defaults)
        let headphone = PresetFile(name: "Headphones", preampDb: -4, bands: Presets.bassBoost)
        let speaker = PresetFile(name: "Speakers", preampDb: -2, bands: Presets.vocal)
        try store.set(headphone, for: "headphone-uid")
        try store.set(speaker, for: "speaker-uid")

        let reopened = OutputPresetStore(defaults: defaults)
        #expect(reopened.preset(for: "headphone-uid")?.preampDb == -4)
        #expect(reopened.preset(for: "speaker-uid")?.name == "Speakers")
        #expect(reopened.preset(for: "unassigned") == nil)
        try reopened.set(nil, for: "headphone-uid")
        #expect(store.preset(for: "headphone-uid") == nil)
        #expect(store.preset(for: "speaker-uid")?.name == "Speakers")
    }
}
