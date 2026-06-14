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
        bands.map {
            EQBand(frequency: $0.frequency, gain: $0.gain, q: $0.q, type: $0.type,
                   enabled: $0.enabled, slopeDbPerOct: $0.slopeDbPerOct)
        }
    }
}

struct PortableBand: Codable {
    var type: FilterType
    var frequency: Double
    var gain: Float
    var q: Double
    var enabled: Bool
    var slopeDbPerOct: Double

    init(_ band: EQBand) {
        type = band.type
        frequency = band.frequency
        gain = band.gain
        q = band.q
        enabled = band.enabled
        slopeDbPerOct = band.slopeDbPerOct
    }

    // Tolerant decode: presets written before slope existed default to 12 dB/oct.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(FilterType.self, forKey: .type)
        frequency = try c.decode(Double.self, forKey: .frequency)
        gain = try c.decode(Float.self, forKey: .gain)
        q = try c.decode(Double.self, forKey: .q)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        slopeDbPerOct = try c.decodeIfPresent(Double.self, forKey: .slopeDbPerOct) ?? 12
    }
}
