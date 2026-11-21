import Foundation

enum AutoEqTextPreset {
    private static let filterTypes: [String: FilterType] = ["PK": .peaking, "LSC": .lowShelf, "HSC": .highShelf]

    static func read(_ text: String, name: String) throws -> PresetFile {
        var preamp: Float?
        var bands: [EQBand] = []
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (index, line) in lines.enumerated() {
            let statement = line.prefix { $0 != "#" }.trimmingCharacters(in: .whitespaces)
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
            } else if command.first == "filter", command.count == 1 ||
                        (command.count == 2 && (Int(command[1]) ?? 0) > 0) {
                guard let band = filter(values) else { throw error }
                bands.append(band)
                guard bands.count <= MobileEQ.maximumBandCount else { throw PresetError.tooManyFilters }
            } else {
                throw error
            }
        }
        guard !bands.isEmpty else { throw PresetError.invalidFile }
        return PresetFile(name: name, preampDb: preamp ?? 0, bands: bands)
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
