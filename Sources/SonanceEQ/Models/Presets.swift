import Foundation

/// Built-in starter presets for the M0/M1 10-band graphic EQ.
/// The full curated library + 6,000+ AutoEq headphone corrections land in M2.
enum Presets {
    /// ISO octave-spaced center frequencies for a classic 10-band graphic EQ.
    static let isoCenters: [Double] = [31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    /// Q for octave-spaced peaking bands (≈ 1.414 keeps adjacent bands smoothly overlapping).
    static let graphicQ = 1.414

    static func graphic(gains: [Float]) -> [EQBand] {
        zip(isoCenters, gains).map { freq, gain in
            EQBand(frequency: freq, gain: gain, q: graphicQ, type: .peaking)
        }
    }

    static var flat: [EQBand] { graphic(gains: Array(repeating: 0, count: isoCenters.count)) }

    static var bassBoost: [EQBand] {
        graphic(gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0])
    }

    static var trebleBoost: [EQBand] {
        graphic(gains: [0, 0, 0, 0, 0, 0, 2, 4, 5, 6])
    }

    static var vocal: [EQBand] {
        graphic(gains: [-3, -2, -1, 1, 3, 4, 3, 1, 0, -1])
    }

    static var loudness: [EQBand] {
        // Smile/V-shape: boost lows + highs for low-volume listening.
        graphic(gains: [6, 4, 2, 0, -1, -1, 0, 2, 4, 5])
    }

    struct Item: Identifiable {
        let id = UUID()
        let name: String
        let bands: [EQBand]
    }

    static var all: [Item] {
        [
            Item(name: "Flat", bands: flat),
            Item(name: "Bass Boost", bands: bassBoost),
            Item(name: "Treble", bands: trebleBoost),
            Item(name: "Vocal", bands: vocal),
            Item(name: "Loudness", bands: loudness),
        ]
    }
}
