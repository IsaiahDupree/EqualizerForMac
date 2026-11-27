import Foundation

enum AutoEqTextPreset {
    private static let filterTypes: [String: FilterType] = ["PK": .peaking, "LSC": .lowShelf, "HSC": .highShelf]
    private static let graphicBandCount = MobileEQ.maximumBandCount

    private struct GraphicPoint {
        let frequency: Double
        let gain: Double
    }

    static func read(_ text: String, name: String) throws -> PresetFile {
        var preamp: Float?
        var bands: [EQBand] = []
        var graphicPoints: [GraphicPoint]?
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (index, line) in lines.enumerated() {
            let statement = line.replacingOccurrences(of: "\u{FEFF}", with: "")
                .prefix { $0 != "#" }.trimmingCharacters(in: .whitespaces)
            if statement.isEmpty { continue }
            let error = PresetError.unsupportedAutoEqLine(index + 1)
            let fields = statement.split(separator: ":", maxSplits: 1)
            guard fields.count == 2 else { throw error }
            let command = fields[0].lowercased().split(whereSeparator: \.isWhitespace)
            let values = fields[1].uppercased().split(whereSeparator: \.isWhitespace)
            if command == ["preamp"] {
                guard preamp == nil, values.count == 2, values[1] == "DB", let gain = Float(values[0]) else {
                    throw error
                }
                preamp = gain
            } else if command == ["graphiceq"] {
                guard graphicPoints == nil, bands.isEmpty else { throw error }
                graphicPoints = try parseGraphicEQ(String(fields[1]), line: index + 1)
            } else if command.first == "filter", command.count == 1 ||
                        (command.count == 2 && (Int(command[1]) ?? 0) > 0) {
                guard graphicPoints == nil else { throw error }
                guard let band = filter(values) else { throw error }
                bands.append(band)
                guard bands.count <= MobileEQ.maximumBandCount else { throw PresetError.tooManyFilters }
            } else {
                throw error
            }
        }
        if let graphicPoints {
            return try graphicPreset(graphicPoints, name: name, preamp: preamp)
        }
        guard !bands.isEmpty else { throw PresetError.invalidFile }
        return PresetFile(name: name, preampDb: preamp ?? 0, bands: bands)
    }

    static func isGraphicEQ(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { line in
            let statement = line.replacingOccurrences(of: "\u{FEFF}", with: "")
                .prefix { $0 != "#" }.trimmingCharacters(in: .whitespaces)
            return statement.split(separator: ":", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces)
                .caseInsensitiveCompare("GraphicEQ") == .orderedSame
        }
    }

    private static func parseGraphicEQ(_ text: String, line: Int) throws -> [GraphicPoint] {
        let error = PresetError.unsupportedAutoEqLine(line)
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasSuffix(";") { body.removeLast() }
        let pairs = body.split(separator: ";", omittingEmptySubsequences: false)
        guard (2...4_096).contains(pairs.count) else { throw error }
        var points: [GraphicPoint] = []
        points.reserveCapacity(pairs.count)
        for pair in pairs {
            let values = pair.split(whereSeparator: \.isWhitespace)
            guard values.count == 2,
                  let frequency = Double(values[0]), let gain = Double(values[1]),
                  frequency.isFinite, gain.isFinite,
                  (20...20_000).contains(frequency), (-120...120).contains(gain),
                  points.last.map({ frequency > $0.frequency }) ?? true else { throw error }
            points.append(GraphicPoint(frequency: frequency, gain: gain))
        }
        return points
    }

    private static func graphicPreset(_ points: [GraphicPoint], name: String,
                                      preamp: Float?) throws -> PresetFile {
        let first = points[0].frequency
        let last = points[points.count - 1].frequency
        guard last > first else { throw PresetError.invalidFile }
        let logFirst = log(first), logLast = log(last)
        let centers = (0..<graphicBandCount).map { index in
            exp(logFirst + (logLast - logFirst) * Double(index) / Double(graphicBandCount - 1))
        }
        let spacingInOctaves = log2(last / first) / Double(graphicBandCount - 1)
        let q = min(Double(MobileEQ.qualityRange.upperBound),
                    max(Double(MobileEQ.qualityRange.lowerBound),
                        1 / (2 * sinh(log(2) * spacingInOctaves / 2))))
        let sampleFrequencies = (0..<256).map { index in
            exp(logFirst + (logLast - logFirst) * Double(index) / 255)
        }
        let target = sampleFrequencies.map { interpolate(points, at: $0) }
        let basis = centers.map { center in
            sampleFrequencies.map { frequency in
                let coefficients = RBJ.coeffs(type: .peaking, sampleRate: 48_000,
                                              freq: center, gainDb: 1, q: q)
                return FrequencyResponse.magnitudeDb(coefficients, 2 * .pi * frequency / 48_000)
            }
        }

        // Fit band gains against the imported response by coordinate descent.
        // This is deterministic, bounded work (32 × 48 × 256) performed off the UI thread.
        var response = Array(repeating: 0.0, count: sampleFrequencies.count)
        var gains = Array(repeating: 0.0, count: graphicBandCount)
        for _ in 0..<48 {
            for band in 0..<graphicBandCount {
                let shape = basis[band]
                var numerator = 0.0
                var denominator = 0.0
                for sample in shape.indices {
                    let residual = target[sample] - response[sample]
                    numerator += shape[sample] * (residual + shape[sample] * gains[band])
                    denominator += shape[sample] * shape[sample]
                }
                guard denominator > 1e-12 else { continue }
                let next = min(Double(MobileEQ.gainRange.upperBound),
                               max(Double(MobileEQ.gainRange.lowerBound), numerator / denominator))
                let delta = next - gains[band]
                if delta != 0 {
                    for sample in shape.indices { response[sample] += shape[sample] * delta }
                    gains[band] = next
                }
            }
        }

        let filters = zip(centers, gains).map { frequency, gain in
            EQBand(frequency: frequency, gain: Float(gain), q: q, type: .peaking, enabled: abs(gain) >= 0.05)
        }
        var settings = MobileEQSettings(bands: filters, preamp: preamp ?? 0)
        if preamp == nil { settings = settings.applyingEstimatedHeadroom(sampleRate: 48_000) }
        guard settings.isValid else { throw PresetError.outOfRange }
        return PresetFile(name: name, preampDb: settings.preamp, bands: settings.bands)
    }

    private static func interpolate(_ points: [GraphicPoint], at frequency: Double) -> Double {
        if frequency <= points[0].frequency { return points[0].gain }
        if frequency >= points[points.count - 1].frequency { return points[points.count - 1].gain }
        var lower = 0
        var upper = points.count - 1
        while upper - lower > 1 {
            let middle = (lower + upper) / 2
            if points[middle].frequency <= frequency { lower = middle } else { upper = middle }
        }
        let a = points[lower], b = points[upper]
        let fraction = (log(frequency) - log(a.frequency)) / (log(b.frequency) - log(a.frequency))
        return a.gain + (b.gain - a.gain) * fraction
    }

    private static func filter(_ values: [Substring]) -> EQBand? {
        guard values.count == 10, values[0] == "ON" || values[0] == "OFF",
              let type = filterTypes[String(values[1])],
              values[2] == "FC", values[4] == "HZ", let frequency = Double(values[3]),
              values[5] == "GAIN", values[7] == "DB", let gain = Float(values[6]),
              values[8] == "Q", let quality = Double(values[9]) else { return nil }
        return EQBand(frequency: frequency, gain: gain, q: quality, type: type, enabled: values[0] == "ON")
    }
}
