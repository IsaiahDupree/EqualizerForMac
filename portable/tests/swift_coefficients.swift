import Foundation

// Compile with the actual shipping Biquad/EQBand/FilterDesigner sources, as main.swift.
while let line = readLine() {
    let fields = line.split(separator: " ").map(String.init)
    guard fields.count == 6, let type = FilterType(rawValue: fields[0]),
          let rate = Double(fields[1]), let frequency = Double(fields[2]),
          let gain = Float(fields[3]), let q = Double(fields[4]),
          let slope = Double(fields[5]) else {
        fatalError("Invalid coefficient parity request")
    }
    let band = EQBand(frequency: frequency, gain: gain, q: q, type: type,
                      slopeDbPerOct: slope)
    let rows = FilterDesigner.sections(for: band, sampleRate: rate).map {
        [Double($0.b0), Double($0.b1), Double($0.b2), Double($0.a1), Double($0.a2)]
    }
    let data = try JSONSerialization.data(withJSONObject: rows)
    print(String(decoding: data, as: UTF8.self))
}
