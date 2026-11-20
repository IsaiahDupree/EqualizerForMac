import SwiftUI

struct ResponsePlot: View {
    let bands: [EQBand]
    let sampleRate: Double
    let selection: Int
    let bypassed: Bool

    private let panel = Color(red: 0.07, green: 0.10, blue: 0.19)
    private let trace = Color(red: 0.57, green: 0.73, blue: 1)

    var body: some View {
        let upper = min(20_000, sampleRate / 2 - 1)
        let response = FrequencyResponse.curve(bands: bypassed ? [] : bands.filter { $0.frequency <= upper },
                                               sampleRate: sampleRate, points: 145, fMax: upper)
        Canvas { context, size in
            let plot = CGRect(x: 35, y: 17, width: size.width - 54, height: size.height - 43)
            guard plot.width > 0, plot.height > 0 else { return }
            func x(_ frequency: Double) -> Double {
                plot.minX + plot.width * log10(frequency / 20) / log10(upper / 20)
            }
            func y(_ db: Double) -> Double {
                plot.midY - plot.height * min(max(db, -18), 18) / 36
            }
            func rule(from start: CGPoint, to end: CGPoint, opacity: Double) {
                let path = Path {
                    $0.move(to: start)
                    $0.addLine(to: end)
                }
                context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: 1)
            }

            for gain in [-12.0, 0, 12] {
                let row = y(gain)
                rule(from: CGPoint(x: plot.minX, y: row), to: CGPoint(x: plot.maxX, y: row),
                     opacity: gain == 0 ? 0.26 : 0.14)
                let label = gain > 0 ? "+\(Int(gain))" : "\(Int(gain))"
                context.draw(Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.64)),
                             at: CGPoint(x: plot.minX - 7, y: row), anchor: .trailing)
            }
            for (hz, label) in [(20.0, "20"), (100, "100"), (1_000, "1k"), (10_000, "10k"), (20_000, "20k")] where hz <= upper {
                let column = x(hz)
                rule(from: CGPoint(x: column, y: plot.minY), to: CGPoint(x: column, y: plot.maxY), opacity: 0.14)
                context.draw(Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.64)),
                             at: CGPoint(x: column, y: plot.maxY + 11))
            }

            let points = response.map { CGPoint(x: x($0.freq), y: y($0.db)) }
            guard let first = points.first, let last = points.last else { return }
            let line = Path { path in
                path.move(to: first)
                path.addLines(points)
            }
            var fill = line
            fill.addLine(to: CGPoint(x: last.x, y: plot.maxY))
            fill.addLine(to: CGPoint(x: first.x, y: plot.maxY))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(Gradient(colors: [trace.opacity(0.28), trace.opacity(0.02)]),
                                                     startPoint: CGPoint(x: 0, y: plot.minY),
                                                     endPoint: CGPoint(x: 0, y: plot.maxY)))
            context.stroke(line, with: .color(bypassed ? .white.opacity(0.65) : trace),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            for (index, band) in bands.enumerated() where band.frequency <= upper {
                let radius = index == selection ? 5.0 : 3.0
                let column = x(band.frequency)
                let row = y(bypassed ? 0 : Double(band.gain))
                let marker = Path(ellipseIn: CGRect(x: column - radius, y: row - radius,
                                                    width: radius * 2, height: radius * 2))
                context.fill(marker, with: .color(index == selection ? .white : trace))
            }
        }
        .frame(height: 172)
        .background(panel, in: RoundedRectangle(cornerRadius: 15))
        .accessibilityLabel(bypassed ? "Equalizer response, bypassed" : "Equalizer frequency response in decibels")
    }
}
