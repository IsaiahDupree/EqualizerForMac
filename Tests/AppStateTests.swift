import Foundation
import Testing
@testable import SonanceEQ

@MainActor
@Suite struct AppStateTests {
    @Test func addBandAppendsToActiveChain() {
        let app = AppState()
        let before = app.bands.count
        app.addBand()
        #expect(app.bands.count == before + 1)
    }

    @Test func removeBandWorks() {
        let app = AppState()
        let id = app.addBand()!
        app.removeBand(id: id)
        #expect(!app.bands.contains { $0.id == id })
    }

    @Test func bandCountIsCappedAtMax() {
        let app = AppState()
        app.bands = []
        for _ in 0..<40 { app.addBand() }
        #expect(app.bands.count <= EQEngine.maxBands)
    }

    @Test func enablingMidSideSeedsFlatSideCurve() {
        let app = AppState()
        app.sideBands = []
        app.setMidSide(true)
        #expect(!app.sideBands.isEmpty)
        #expect(app.sideBands.allSatisfy { $0.gain == 0 })
    }

    @Test func editTargetRedirectsActiveBands() {
        let app = AppState()
        app.setMidSide(true)
        app.editTarget = .side
        app.activeBands = [EQBand(frequency: 500, gain: 2, q: 1, type: .peaking)]
        #expect(app.sideBands.count == 1)
        #expect(app.bands.count == 10)   // Mid chain untouched
    }

    @Test func disablingMidSideResetsEditTarget() {
        let app = AppState()
        app.setMidSide(true)
        app.editTarget = .side
        app.setMidSide(false)
        #expect(app.editTarget == .mid)
    }

    @Test func resetFlatZerosActiveChain() {
        let app = AppState()
        app.bands[0].gain = 6
        app.resetFlat()
        #expect(app.bands.allSatisfy { $0.gain == 0 })
    }

    @Test func applyAutoEqLoadsBandsPreampAndName() {
        let app = AppState()
        let preset = AutoEqPreset(id: 1, model: "HD 600", brand: "Sennheiser", category: "over-ear",
                                  source: "oratory1990", preampDb: -6,
                                  filtersJSON: #"[{"type":"peaking","frequency":1000,"gain":3,"q":1}]"#)
        app.applyAutoEq(preset)
        #expect(app.bands.count == 1)
        #expect(app.preampDb == -6)
        #expect(app.activePresetName == "HD 600 · oratory1990")
    }

    @Test func latencyIsZeroInMinimumPhase() {
        let app = AppState()
        app.linearPhase = false
        #expect(app.latencyMs == 0)
    }

    @Test func latencyIsPositiveInLinearPhase() {
        let app = AppState()
        app.linearPhase = true
        #expect(app.latencyMs > 0)
    }

    @Test func applyingPresetSetsBands() {
        let app = AppState()
        app.apply(Presets.bassBoost)
        #expect(app.bands.count == 10)
        #expect(app.bands[0].gain > 0)
    }
}
