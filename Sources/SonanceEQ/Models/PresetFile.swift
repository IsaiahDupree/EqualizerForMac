import Foundation

/// Portable, versioned preset file for import/export. Deliberately separate from `EQBand` so the
/// on-disk shape is stable (no UUIDs) and forward-compatible.
struct PresetFile: Codable {
    var app = "SonanceEQ"
    var version = 1
    var name: String
    var preampDb: Float
    var bands: [PortableBand]

    init(name: String, preampDb: Float, bands: [EQBand]) {
        self.name = name
        self.preampDb = preampDb
        self.bands = bands.map(PortableBand.init)
    }

    /// Materialize into live EQ bands.
    func eqBands() -> [EQBand] {
        bands.map { EQBand(frequency: $0.frequency, gain: $0.gain, q: $0.q, type: $0.type, enabled: $0.enabled) }
    }
}

struct PortableBand: Codable {
    var type: FilterType
    var frequency: Double
    var gain: Float
    var q: Double
    var enabled: Bool

    init(_ band: EQBand) {
        type = band.type
        frequency = band.frequency
        gain = band.gain
        q = band.q
        enabled = band.enabled
    }
}
