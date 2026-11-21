import SwiftUI

struct ResponsePlot: View {
    struct Interaction {
        let select: (Int) -> Void
        let move: (Int, Double, Float) -> Void
        let editingChanged: (Bool) -> Void
    }

    let bands: [EQBand]
    let sampleRate: Double
    let selection: Int?
    let bypassed: Bool
    var interaction: Interaction?

    @GestureState private var touchingBand = false
    @State private var drag: BandDrag?

    private let panel = Color(red: 0.07, green: 0.10, blue: 0.19)
    private let trace = Color(red: 0.57, green: 0.73, blue: 1)
    private let touchRadius = 22.0

    var body: some View {
        GeometryReader { geometry in
            let scale = PlotScale(size: geometry.size, sampleRate: sampleRate)
            let points = bands.enumerated().compactMap { index, band -> BandPoint? in
                guard band.enabled, band.frequency <= scale.highestFrequency else { return nil }
                let gain = band.type.usesGain ? Double(band.gain) : 0
                return BandPoint(index: index, location: scale.point(frequency: band.frequency, gain: gain))
            }

            Canvas { context, _ in
                guard scale.bounds.width > 0, scale.bounds.height > 0 else { return }
                drawGrid(in: context, scale: scale)
                drawResponse(in: context, scale: scale)
                for point in points where point.index != selection { drawHandle(point, in: context) }
                if let selected = points.first(where: { $0.index == selection }) {
                    drawHandle(selected, in: context)
                }
            }
            .overlay {
                if let interaction {
                    Color.clear
                        .contentShape(BandTouchArea(points: points.map(\.location), radius: touchRadius))
                        .highPriorityGesture(bandGesture(points: points, scale: scale, interaction: interaction))
                }
            }
        }
        .frame(height: 202)
        .background(panel, in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: touchingBand) { _, touching in
            if !touching { finishDrag() }
        }
        .onDisappear(perform: finishDrag)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bypassed ? "Equalizer response, bypassed" : "Equalizer frequency response in decibels")
        .accessibilityIdentifier("eqResponse")
    }

    private func bandGesture(points: [BandPoint], scale: PlotScale, interaction: Interaction) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touchingBand) { _, touching, _ in touching = true }
            .onChanged { value in
                if drag == nil {
                    let candidates = points.filter { $0.distance(to: value.startLocation) <= touchRadius }
                    let nearest = candidates.min { first, second in
                        let firstDistance = first.distance(to: value.startLocation)
                        let secondDistance = second.distance(to: value.startLocation)
                        if firstDistance == secondDistance { return first.index == selection && second.index != selection }
                        return firstDistance < secondDistance
                    }
                    guard let nearest else { return }
                    drag = BandDrag(point: nearest)
                    interaction.editingChanged(true)
                    interaction.select(nearest.index)
                }
                moveBand(by: value.translation, scale: scale)
            }
            .onEnded { value in
                moveBand(by: value.translation, scale: scale)
                finishDrag()
            }
    }

    private func moveBand(by translation: CGSize, scale: PlotScale) {
        guard var drag else { return }
        if !drag.moved {
            guard hypot(translation.width, translation.height) >= 3 else { return }
            drag.moved = true
            self.drag = drag
        }
        let location = CGPoint(x: drag.point.location.x + translation.width,
                               y: drag.point.location.y + translation.height)
        let (frequency, gain) = scale.values(at: location)
        interaction?.move(drag.point.index, frequency, gain)
    }

    private func finishDrag() {
        guard drag != nil else { return }
        drag = nil
        interaction?.editingChanged(false)
    }

    private func drawGrid(in context: GraphicsContext, scale: PlotScale) {
        let plot = scale.bounds
        func rule(from start: CGPoint, to end: CGPoint, opacity: Double) {
            let path = Path {
                $0.move(to: start)
                $0.addLine(to: end)
            }
            context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: 1)
        }

        for gain in [-24.0, -12, 0, 12, 24] {
            let row = scale.y(gain)
            rule(from: CGPoint(x: plot.minX, y: row), to: CGPoint(x: plot.maxX, y: row),
                 opacity: gain == 0 ? 0.28 : 0.15)
            let label = gain > 0 ? "+\(Int(gain))" : "\(Int(gain))"
            context.draw(axisLabel(label), at: CGPoint(x: plot.minX - 7, y: row), anchor: .trailing)
        }
        for (hz, label) in [(20.0, "20"), (100, "100"), (1_000, "1k"), (10_000, "10k"), (20_000, "20k")]
            where hz <= scale.highestFrequency {
            let column = scale.x(hz)
            rule(from: CGPoint(x: column, y: plot.minY), to: CGPoint(x: column, y: plot.maxY), opacity: 0.15)
            context.draw(axisLabel(label), at: CGPoint(x: column, y: plot.maxY + 12))
        }
    }

    private func axisLabel(_ label: String) -> Text {
        Text(label).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.72))
    }

    private func drawResponse(in context: GraphicsContext, scale: PlotScale) {
        let active = bypassed ? [] : bands.filter {
            $0.frequency <= scale.highestFrequency && (!$0.type.usesGain || $0.gain != 0)
        }
        let response = FrequencyResponse.curve(bands: active, sampleRate: sampleRate, points: 145,
                                               fMax: scale.highestFrequency)
        let points = response.map { scale.point(frequency: $0.freq, gain: $0.db) }
        guard let first = points.first, let last = points.last else { return }
        let line = Path { path in
            path.move(to: first)
            path.addLines(points)
        }
        if !bypassed {
            var fill = line
            fill.addLine(to: CGPoint(x: last.x, y: scale.bounds.maxY))
            fill.addLine(to: CGPoint(x: first.x, y: scale.bounds.maxY))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(Gradient(colors: [trace.opacity(0.29), trace.opacity(0.015)]),
                             startPoint: CGPoint(x: 0, y: scale.bounds.minY),
                             endPoint: CGPoint(x: 0, y: scale.bounds.maxY)))
        }
        context.stroke(line, with: .color(bypassed ? .white.opacity(0.55) : trace),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: bypassed ? [4, 5] : []))
    }

    private func drawHandle(_ point: BandPoint, in context: GraphicsContext) {
        let isSelected = point.index == selection
        if isSelected {
            context.fill(Path(ellipseIn: point.bounds(radius: 11)), with: .color(trace.opacity(0.28)))
        }
        context.fill(Path(ellipseIn: point.bounds(radius: isSelected ? 6 : 4.5)),
                     with: .color(isSelected ? .white : trace))
    }
}

private struct BandPoint {
    let index: Int
    let location: CGPoint

    func distance(to touch: CGPoint) -> Double { hypot(location.x - touch.x, location.y - touch.y) }

    func bounds(radius: Double) -> CGRect {
        CGRect(x: location.x - radius, y: location.y - radius, width: 2 * radius, height: 2 * radius)
    }
}

private struct BandDrag {
    let point: BandPoint
    var moved = false
}

private struct BandTouchArea: Shape {
    let points: [CGPoint]
    let radius: Double

    func path(in rect: CGRect) -> Path {
        Path { path in
            for point in points {
                path.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius))
            }
        }
    }
}

private struct PlotScale {
    let bounds: CGRect
    let highestFrequency: Double
    private let minimumFrequency = Double(MobileEQ.frequencyRange.lowerBound)
    private let chartGain = 27.0

    init(size: CGSize, sampleRate: Double) {
        bounds = CGRect(x: 36, y: 16, width: max(1, size.width - 58), height: max(1, size.height - 42))
        highestFrequency = MobileEQ.highestFrequency(at: sampleRate)
    }

    func x(_ hz: Double) -> Double {
        bounds.minX + bounds.width * log10(hz / minimumFrequency) / log10(highestFrequency / minimumFrequency)
    }

    func y(_ db: Double) -> Double {
        bounds.midY - bounds.height * min(max(db, -chartGain), chartGain) / (2 * chartGain)
    }

    func point(frequency: Double, gain: Double) -> CGPoint { CGPoint(x: x(frequency), y: y(gain)) }

    func values(at location: CGPoint) -> (frequency: Double, gain: Float) {
        let position = min(max((location.x - bounds.minX) / bounds.width, 0), 1)
        let frequency = minimumFrequency * pow(highestFrequency / minimumFrequency, position)
        let db = (bounds.midY - location.y) * 2 * chartGain / bounds.height
        return (min(frequency, highestFrequency), min(max(Float(db), MobileEQ.gainRange.lowerBound), MobileEQ.gainRange.upperBound))
    }
}
