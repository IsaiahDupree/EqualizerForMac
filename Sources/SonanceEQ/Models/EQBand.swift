import Foundation

/// One band of the equalizer. The same model backs every UI skin (graphic / parametric).
struct EQBand: Identifiable, Codable, Equatable {
    var id = UUID()
    var frequency: Double   // Hz
    var gain: Float         // dB
    var q: Double
    var type: FilterType
    var enabled: Bool = true
    /// Slope for Low/High Cut filters, in dB/octave (6,12,18,24,36,48,72,96). Ignored by other shapes.
    var slopeDbPerOct: Double = 12

    /// Human-readable center-frequency label (e.g. "1k", "16k", "250").
    var freqLabel: String {
        if frequency >= 1000 {
            let k = frequency / 1000
            return k == k.rounded() ? "\(Int(k))k" : String(format: "%.1fk", k)
        }
        return "\(Int(frequency.rounded()))"
    }

    var gainLabel: String { String(format: "%+.1f", gain) }
}
