import SwiftUI

/// Parametric EQ editor: a live magnitude-response curve with draggable band handles and an inspector.
/// Drag a handle horizontally to move frequency, vertically to change gain (for gain-bearing filters);
/// the curve and audio update live (coefficients ramp, so no zipper noise).
struct ResponseCurveView: View {
    @Bindable var app: AppState
    @State private var selectedBandID: UUID?

    private let gainRange: Double = 15        // ± dB shown on the vertical axis
    private let fMin = 20.0, fMax = 20_000.0

    var body: some View {
        VStack(spacing: 8) {
            curve
            inspector
        }
    }

    // MARK: Curve + handles

    private var curve: some View {
        GeometryReader { geo in
            let g = CurveGeometry(size: geo.size, gainRange: gainRange, fMin: fMin, fMax: fMax)
            ZStack {
                Canvas { ctx, _ in
                    drawGrid(&ctx, g)
                    drawCurve(&ctx, g)
                }
                // Tap empty space to deselect.
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { selectedBandID = nil }
                ForEach(app.activeBands) { band in
                    handle(band, g)
                }
            }
            .overlay(alignment: .topTrailing) { addButton }
        }
        .frame(height: 190)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
    }

    private var addButton: some View {
        Button {
            if let id = app.addBand() { selectedBandID = id }
        } label: {
            Label("Band", systemImage: "plus")
        }
        .controlSize(.small)
        .padding(6)
        .disabled(app.activeBands.count >= EQEngine.maxBands)
    }

    private func handle(_ band: EQBand, _ g: CurveGeometry) -> some View {
        let selected = band.id == selectedBandID
        return Circle()
            .fill(selected ? Color.accentColor : Color.primary.opacity(0.55))
            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
            .frame(width: selected ? 15 : 11, height: selected ? 15 : 11)
            .position(x: g.x(band.frequency), y: g.y(Double(band.gain)))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectedBandID = band.id
                        guard let i = app.activeBands.firstIndex(where: { $0.id == band.id }) else { return }
                        app.activeBands[i].frequency = g.freq(value.location.x).clamped(fMin, fMax)
                        if app.activeBands[i].type.usesGain {
                            app.activeBands[i].gain = Float(g.db(value.location.y).clamped(-gainRange, gainRange))
                        }
                        app.pushSettings()
                    }
            )
    }

    // MARK: Inspector

    @ViewBuilder private var inspector: some View {
        if let id = selectedBandID, let i = app.activeBands.firstIndex(where: { $0.id == id }) {
            HStack(spacing: 10) {
                Picker("", selection: bind(\.type, at: i)) {
                    ForEach(FilterType.allCases) { Text($0.shortLabel).tag($0) }
                }
                .labelsHidden().frame(width: 72)

                Text("\(app.activeBands[i].freqLabel) Hz")
                    .font(.caption.monospaced()).frame(width: 64, alignment: .leading)

                HStack(spacing: 4) {
                    Text("Q").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: bind(\.q, at: i), in: 0.1...10)
                    Text(String(format: "%.2f", app.activeBands[i].q))
                        .font(.caption2.monospaced()).frame(width: 32)
                }

                Text(app.activeBands[i].type.usesGain ? String(format: "%+.1f dB", app.activeBands[i].gain) : "—")
                    .font(.caption2.monospaced()).frame(width: 52, alignment: .trailing)

                Button(role: .destructive) {
                    app.removeBand(id: id); selectedBandID = nil
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            .frame(height: 22)
        } else {
            HStack {
                Text("Drag a handle to shape the curve · tap a handle to edit Q & type")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(height: 22)
        }
    }

    /// Two-way binding to a band field that pushes to the audio engine on change.
    private func bind<V>(_ key: WritableKeyPath<EQBand, V>, at i: Int) -> Binding<V> {
        Binding(
            get: { app.activeBands[i][keyPath: key] },
            set: { app.activeBands[i][keyPath: key] = $0; app.pushSettings() }
        )
    }

    // MARK: Drawing

    private func drawGrid(_ ctx: inout GraphicsContext, _ g: CurveGeometry) {
        let freqLines: [(Double, String?)] = [
            (31.25, "31"), (62.5, nil), (125, "125"), (250, nil), (500, "500"),
            (1000, nil), (2000, "2k"), (4000, nil), (8000, "8k"), (16000, nil),
        ]
        for (f, label) in freqLines {
            let x = g.x(f)
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: g.size.height))
            ctx.stroke(path, with: .color(.gray.opacity(0.18)), lineWidth: 1)
            if let label {
                ctx.draw(Text(label).font(.system(size: 8)).foregroundColor(.secondary),
                         at: CGPoint(x: x + 1, y: g.size.height - 7), anchor: .leading)
            }
        }
        for db in stride(from: -12.0, through: 12.0, by: 6.0) {
            let y = g.y(db)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: g.size.width, y: y))
            ctx.stroke(path, with: .color(db == 0 ? .gray.opacity(0.45) : .gray.opacity(0.18)),
                       lineWidth: db == 0 ? 1.2 : 1)
            if db != 0 {
                ctx.draw(Text("\(Int(db))").font(.system(size: 8)).foregroundColor(.secondary),
                         at: CGPoint(x: 2, y: y - 6), anchor: .leading)
            }
        }
    }

    private func drawCurve(_ ctx: inout GraphicsContext, _ g: CurveGeometry) {
        // In Mid-Side mode, draw the inactive chain faintly for context.
        if app.midSideEnabled {
            let other = app.editTarget == .side ? app.bands : app.sideBands
            strokeCurve(&ctx, g, bands: other, color: .gray.opacity(0.45), width: 1.2, fill: false)
        }
        strokeCurve(&ctx, g, bands: app.activeBands, color: .accentColor, width: 2, fill: true)
    }

    private func strokeCurve(_ ctx: inout GraphicsContext, _ g: CurveGeometry,
                             bands: [EQBand], color: Color, width: CGFloat, fill: Bool) {
        let points = FrequencyResponse.curve(bands: bands, sampleRate: app.sampleRateHz, fMin: fMin, fMax: fMax)
        guard !points.isEmpty else { return }

        var line = Path()
        var fillPath = Path()
        fillPath.move(to: CGPoint(x: 0, y: g.y(0)))
        for (idx, p) in points.enumerated() {
            let pt = CGPoint(x: g.x(p.freq), y: g.y(p.db.clamped(-gainRange, gainRange)))
            if idx == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            fillPath.addLine(to: pt)
        }
        if fill {
            fillPath.addLine(to: CGPoint(x: g.size.width, y: g.y(0)))
            fillPath.closeSubpath()
            ctx.fill(fillPath, with: .linearGradient(
                Gradient(colors: [color.opacity(0.28), color.opacity(0.04)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: g.size.height)))
        }
        ctx.stroke(line, with: .color(color), lineWidth: width)
    }
}

/// Maps frequency (log) and gain (dB) to/from view coordinates.
private struct CurveGeometry {
    let size: CGSize
    let gainRange: Double
    let fMin: Double
    let fMax: Double

    private var logMin: Double { log10(fMin) }
    private var logMax: Double { log10(fMax) }

    func x(_ freq: Double) -> CGFloat {
        CGFloat((log10(freq) - logMin) / (logMax - logMin)) * size.width
    }
    func freq(_ x: CGFloat) -> Double {
        pow(10, logMin + Double(x / max(size.width, 1)) * (logMax - logMin))
    }
    func y(_ db: Double) -> CGFloat {
        size.height / 2 - CGFloat(db / gainRange) * (size.height / 2)
    }
    func db(_ y: CGFloat) -> Double {
        Double((size.height / 2 - y) / (size.height / 2)) * gainRange
    }
}

private extension Comparable {
    func clamped(_ low: Self, _ high: Self) -> Self { min(max(self, low), high) }
}
