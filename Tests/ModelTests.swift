import Foundation
import Testing
@testable import SonanceEQ

@Suite struct EQBandTests {
    static let freqLabelCases: [(Double, String)] = [
        (20, "20"), (31.25, "31"), (62.5, "63"), (100, "100"), (125, "125"), (250, "250"),
        (440, "440"), (500, "500"), (999, "999"), (1000, "1k"), (1500, "1.5k"), (2000, "2k"),
        (3500, "3.5k"), (4000, "4k"), (8000, "8k"), (10000, "10k"), (16000, "16k"), (20000, "20k"),
    ]
    @Test(arguments: freqLabelCases)
    func freqLabelFormatting(_ c: (Double, String)) {
        let band = EQBand(frequency: c.0, gain: 0, q: 1, type: .peaking)
        #expect(band.freqLabel == c.1)
    }

    static let gainLabelCases: [(Float, String)] = [
        (0, "+0.0"), (3, "+3.0"), (-3, "-3.0"), (6.5, "+6.5"), (-12, "-12.0"), (1.25, "+1.2"), (9, "+9.0"),
    ]
    @Test(arguments: gainLabelCases)
    func gainLabelFormatting(_ c: (Float, String)) {
        let band = EQBand(frequency: 1000, gain: c.0, q: 1, type: .peaking)
        #expect(band.gainLabel == c.1)
    }

    @Test func bandIsCodableRoundTrip() throws {
        let band = EQBand(frequency: 1234, gain: -4.5, q: 2.2, type: .highShelf, enabled: false)
        let data = try JSONEncoder().encode(band)
        let back = try JSONDecoder().decode(EQBand.self, from: data)
        #expect(back == band)
    }

    @Test(arguments: FilterType.allCases)
    func usesGainMatchesType(_ type: FilterType) {
        let expected = [.peaking, .lowShelf, .highShelf].contains(type)
        #expect(type.usesGain == expected)
    }

    @Test(arguments: FilterType.allCases)
    func shortLabelsAreUnique(_ type: FilterType) {
        #expect(!type.shortLabel.isEmpty)
    }
}

@Suite struct PresetFileTests {
    @Test(arguments: Presets.all.map(\.bands))
    func roundTripPreservesBands(_ bands: [EQBand]) throws {
        let file = PresetFile(name: "T", preampDb: -3, bands: bands)
        let data = try JSONEncoder().encode(file)
        let back = try JSONDecoder().decode(PresetFile.self, from: data)
        let result = back.eqBands()
        #expect(result.count == bands.count)
        for (a, b) in zip(result, bands) {
            #expect(a.frequency == b.frequency && a.gain == b.gain && a.type == b.type)
        }
        #expect(back.preampDb == -3)
    }

    @Test func portableBandMapsAllFields() {
        let band = EQBand(frequency: 800, gain: 5, q: 1.7, type: .lowShelf, enabled: false)
        let p = PortableBand(band)
        #expect(p.frequency == 800 && p.gain == 5 && p.q == 1.7 && p.type == .lowShelf && p.enabled == false)
    }

    @Test func defaultMetadata() {
        let file = PresetFile(name: "X", preampDb: 0, bands: [])
        #expect(file.app == "SonanceEQ" && file.version == 1)
    }
}

@Suite struct PresetsTests {
    @Test(arguments: Presets.all)
    func everyPresetHasTenBands(_ item: Presets.Item) {
        #expect(item.bands.count == 10)
    }

    @Test(arguments: Presets.all)
    func everyPresetBandIsStarting(_ item: Presets.Item) {
        #expect(item.bands.allSatisfy { $0.type == .peaking })
    }

    @Test func flatIsAllZero() {
        #expect(Presets.flat.allSatisfy { $0.gain == 0 })
    }

    @Test func isoCentersAreOctaveSpaced() {
        #expect(Presets.isoCenters.count == 10)
        #expect(Presets.isoCenters.first == 31.25 && Presets.isoCenters.last == 16000)
    }
}

@Suite struct AutoEqPresetTests {
    static let jsonCases: [(String, Int)] = [
        (#"[{"type":"peaking","frequency":1000,"gain":3,"q":1}]"#, 1),
        (#"[{"type":"lowShelf","frequency":105,"gain":6.3,"q":0.7},{"type":"peaking","frequency":2000,"gain":-2,"q":1.5}]"#, 2),
        (#"[{"type":"highShelf","frequency":10000,"gain":-1,"q":0.7}]"#, 1),
        ("[]", 0),
    ]
    @Test(arguments: jsonCases)
    func filtersParseToBands(_ c: (String, Int)) {
        let preset = AutoEqPreset(id: 1, model: "M", brand: "B", category: "in-ear", source: "S", preampDb: -6, filtersJSON: c.0)
        #expect(preset.bands().count == c.1)
    }

    @Test func filterFieldsMapCorrectly() {
        let json = #"[{"type":"lowShelf","frequency":105,"gain":6.3,"q":0.7}]"#
        let preset = AutoEqPreset(id: 1, model: "M", brand: "B", category: "over-ear", source: "S", preampDb: -6, filtersJSON: json)
        let band = preset.bands().first
        #expect(band?.type == .lowShelf && band?.frequency == 105 && band?.q == 0.7)
    }

    @Test func displayNameJoinsModelAndSource() {
        let preset = AutoEqPreset(id: 1, model: "HD 600", brand: "Sennheiser", category: "over-ear", source: "oratory1990", preampDb: 0, filtersJSON: "[]")
        #expect(preset.displayName == "HD 600 · oratory1990")
    }

    @Test func malformedJSONYieldsNoBands() {
        let preset = AutoEqPreset(id: 1, model: "M", brand: "B", category: "in-ear", source: "S", preampDb: 0, filtersJSON: "not json")
        #expect(preset.bands().isEmpty)
    }
}
