import SwiftUI

enum AudioWorkspace: Hashable {
    case equalizer, live
}

struct AudioWorkspacePicker: View {
    @Binding var workspace: AudioWorkspace

    var body: some View {
        Picker("Audio workspace", selection: $workspace) {
            Text("Equalizer").tag(AudioWorkspace.equalizer)
            Text("Live").tag(AudioWorkspace.live)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("audioWorkspace")
    }
}

struct LiveAudioView: View {
    let active: Bool
    let waitingMessage: String
    let read: () -> AudioAnalysisFrame?

    @State private var frame: AudioAnalysisFrame?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Live Audio").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                if frame != nil {
                    Label("Post EQ", systemImage: "waveform")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if frame == nil {
                Text(waitingMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            levels
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Spectrum").font(.headline).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if let frequency = frame?.dominantFrequency {
                        Text("\(frequency.formatted(.number.precision(.fractionLength(0)))) Hz peak")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .accessibilityIdentifier("spectrumPeak")
                    }
                }
                AudioSpectrumView(frame: frame).frame(height: 184)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Waveform").font(.headline).accessibilityAddTraits(.isHeader)
                AudioWaveformView(frame: frame).frame(height: 112)
            }
        }
        .task(id: active) {
            frame = nil
            guard active else { return }
            while !Task.isCancelled {
                frame = read()
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
    }

    private var levels: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Output Levels").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Peak dBFS").font(.caption).foregroundStyle(.secondary)
            }
            level(frame?.right == nil ? "M" : "L", channel: frame?.left)
            if let right = frame?.right { level("R", channel: right) }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func level(_ channelLabel: String, channel: AudioAnalysisFrame.Channel?) -> some View {
        let peak = channel?.peak ?? -96
        let rms = channel?.rms ?? -96
        let peakText = channel.map { $0.peak.formatted(.number.precision(.fractionLength(1))) } ?? "–"
        return HStack(spacing: 8) {
            Text(channelLabel).font(.caption2.monospaced()).frame(width: 18)
            GeometryReader { geometry in
                let peakX = position(peak) * geometry.size.width
                Capsule()
                    .fill(.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(EqualizerEditor.accent)
                            .frame(width: position(rms) * geometry.size.width)
                    }
                    .overlay(alignment: .leading) {
                        if channel != nil {
                            Capsule().fill(peak >= 0 ? .red : EqualizerEditor.accent)
                                .frame(width: 3)
                                .offset(x: max(0, min(peakX, geometry.size.width - 3)))
                        }
                    }
            }
            .frame(height: 8)
            Text(peakText).font(.caption.monospacedDigit())
                .foregroundStyle(peak >= 0 ? Color.red : .secondary)
                .frame(minWidth: 42, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(channelLabel == "M" ? "Mono output" : channelLabel == "L" ? "Left output" : "Right output")
        .accessibilityValue(channel == nil ? "Waiting for audio" : "\(peakText) dBFS peak")
    }

    private func position(_ db: Float) -> Double { Double(min(max((db + 60) / 60, 0), 1)) }
}

struct AudioSpectrumView: View {
    let frame: AudioAnalysisFrame?

    var body: some View {
        Canvas { context, size in
            let plot = CGRect(x: 36, y: 12, width: max(1, size.width - 53), height: max(1, size.height - 37))
            let upper = frame?.highestFrequency ?? 20_000
            func y(_ db: Double) -> Double { plot.maxY - plot.height * min(max((db + 84) / 84, 0), 1) }
            for db in [0.0, -24, -48, -72] {
                let vertical = y(db)
                rule(in: context, from: CGPoint(x: plot.minX, y: vertical), to: CGPoint(x: plot.maxX, y: vertical))
                context.draw(axis("\(Int(db))"), at: CGPoint(x: plot.minX - 7, y: vertical), anchor: .trailing)
            }
            for (frequency, label) in [(50.0, "50"), (200, "200"), (1_000, "1k"), (5_000, "5k"), (16_000, "16k")]
                where frequency <= upper {
                let horizontal = plot.minX + plot.width * log(frequency / 20) / log(upper / 20)
                rule(in: context, from: CGPoint(x: horizontal, y: plot.minY), to: CGPoint(x: horizontal, y: plot.maxY))
                context.draw(axis(label), at: CGPoint(x: horizontal, y: plot.maxY + 12))
            }
            if let bars = frame?.spectrum, !bars.isEmpty {
                let width = plot.width / Double(bars.count)
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [Color(red: 0.47, green: 0.87, blue: 0.98), Color(red: 0.31, green: 0.47, blue: 0.96)]),
                    startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY))
                for (index, db) in bars.enumerated() {
                    let top = y(Double(db))
                    let bar = CGRect(x: plot.minX + Double(index) * width, y: top, width: width * 0.78, height: plot.maxY - top)
                    context.fill(Path(roundedRect: bar, cornerRadius: 2), with: shading)
                }
            }
        }
        .background(analyzerBackground, in: RoundedRectangle(cornerRadius: 15))
        .accessibilityLabel("Output frequency spectrum")
    }

    private func axis(_ text: String) -> Text {
        Text(text).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.7))
    }
}

struct AudioWaveformView: View {
    let frame: AudioAnalysisFrame?

    var body: some View {
        Canvas { context, size in
            let plot = CGRect(x: 12, y: 10, width: max(1, size.width - 24), height: max(1, size.height - 20))
            rule(in: context, from: CGPoint(x: plot.minX, y: plot.midY), to: CGPoint(x: plot.maxX, y: plot.midY))
            for position in [0.25, 0.5, 0.75] {
                let x = plot.minX + plot.width * position
                rule(in: context, from: CGPoint(x: x, y: plot.minY), to: CGPoint(x: x, y: plot.maxY))
            }
            draw(frame?.right?.waveform ?? [], color: Color(red: 0.38, green: 0.48, blue: 0.98), in: context, plot: plot)
            draw(frame?.left.waveform ?? [], color: Color(red: 0.47, green: 0.87, blue: 0.98), in: context, plot: plot)
        }
        .background(analyzerBackground, in: RoundedRectangle(cornerRadius: 15))
        .accessibilityLabel("Output waveform")
    }

    private func draw(_ samples: [AudioAnalysisFrame.WaveformPoint], color: Color, in context: GraphicsContext, plot: CGRect) {
        guard !samples.isEmpty else { return }
        let step = plot.width / Double(samples.count)
        func y(_ value: Float) -> Double {
            plot.midY - Double(value.isFinite ? min(max(value, -1), 1) : 0) * plot.height * 0.5
        }
        let path = Path { path in
            for (index, sample) in samples.enumerated() {
                let x = plot.minX + Double(index) * step + step * 0.5
                path.move(to: CGPoint(x: x, y: y(sample.maximum)))
                path.addLine(to: CGPoint(x: x, y: y(sample.minimum)))
            }
        }
        context.stroke(path, with: .color(color.opacity(0.86)), lineWidth: max(0.5, step * 0.66))
    }
}

private let analyzerBackground = Color(red: 0.06, green: 0.10, blue: 0.18)

private func rule(in context: GraphicsContext, from: CGPoint, to: CGPoint) {
    let path = Path {
        $0.move(to: from)
        $0.addLine(to: to)
    }
    context.stroke(path, with: .color(.white.opacity(0.14)))
}
