import Foundation

/// One headphone correction from the bundled AutoEq database (see Tools/build_autoeq_db.py).
/// Data © AutoEq (Jaakko Pasanen), MIT — shipped with attribution.
struct AutoEqPreset: Identifiable, Hashable {
    let id: Int
    let model: String
    let brand: String
    let category: String   // "in-ear" | "over-ear" | "earbud" | "other"
    let source: String     // measurement database (oratory1990, Rtings, …)
    let preampDb: Float
    /// Raw JSON filter array, decoded lazily by `bands()`.
    let filtersJSON: String

    /// Decode the stored filters into the app's band model.
    func bands() -> [EQBand] {
        guard let data = filtersJSON.data(using: .utf8),
              let stored = try? JSONDecoder().decode([StoredFilter].self, from: data) else { return [] }
        return stored.map { EQBand(frequency: $0.frequency, gain: $0.gain, q: $0.q, type: $0.type) }
    }

    /// `<model> · <source>` — what the preset list shows.
    var displayName: String { "\(model) · \(source)" }
}

/// On-disk filter shape written by the build tool. Mirrors `EQBand` minus the UUID/enabled fields.
private struct StoredFilter: Decodable {
    let type: FilterType
    let frequency: Double
    let gain: Float
    let q: Double
}
