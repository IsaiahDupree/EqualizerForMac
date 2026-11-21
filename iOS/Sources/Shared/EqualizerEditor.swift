import SwiftUI

struct EqualizerEditor: View {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.58, green: 0.71, blue: 1, alpha: 1)
            : UIColor(red: 0.12, green: 0.35, blue: 0.83, alpha: 1)
    })

    @Binding var settings: MobileEQSettings
    @Binding var selectedBand: Int
    let sampleRate: Double
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Equalizer")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                presets
            }
            ResponsePlot(bands: settings.bands, sampleRate: sampleRate, selection: selectedBand,
                         bypassed: settings.bypassed,
                         interaction: .init(select: { selectedBand = $0 }, move: moveBand, editingChanged: onEditingChanged))
            Toggle("Bypass EQ", isOn: $settings.bypassed)
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("bypassEQ")
            bandControls
        }
    }

    private var presets: some View {
        Menu {
            ForEach(Presets.all, id: \.name) { preset in
                Button(preset.name) {
                    var updated = settings
                    updated.bands = preset.bands
                    updated.preamp = 0
                    settings = updated
                }
            }
        } label: {
            Label("Presets", systemImage: "square.stack")
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
        }
    }

    private var bandControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Filter Bands")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Drag a point to tune")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 6)], spacing: 6) {
                ForEach(settings.bands.indices, id: \.self) { index in
                    bandButton(index, selected: selectedBand == index)
                }
            }
            bandSliders(selectedBand)
            Divider()
            sliderRow("Preamp", id: "eqPreamp", value: "\(settings.preamp.formatted(.number.precision(.fractionLength(1)))) dB") {
                Slider(value: $settings.preamp, in: MobileEQ.preampRange, step: 0.5, onEditingChanged: onEditingChanged)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func bandButton(_ index: Int, selected: Bool) -> some View {
        let band = settings.bands[index]
        return Button {
            selectedBand = index
        } label: {
            Text(band.freqLabel)
                .font(.subheadline.monospacedDigit().weight(selected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected ? Self.accent : .primary)
                .background(selected ? Self.accent.opacity(0.13) : Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Band \(index + 1), \(frequencyLabel(band))")
        .accessibilityIdentifier("eqBand\(index)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func bandSliders(_ index: Int) -> some View {
        let band = settings.bands[index]
        return VStack(spacing: 10) {
            sliderRow("Frequency", id: "eqFrequency", value: frequencyLabel(band)) {
                Slider(value: logFrequency(for: index), in: log10(20)...log10(20_000), onEditingChanged: onEditingChanged)
            }
            sliderRow("Gain", id: "eqGain", value: "\(band.gainLabel) dB") {
                Slider(value: $settings.bands[index].gain, in: MobileEQ.gainRange, step: 0.5,
                       onEditingChanged: onEditingChanged)
            }
            sliderRow("Width (Q)", id: "eqQuality", value: band.q.formatted(.number.precision(.fractionLength(2)))) {
                Slider(value: $settings.bands[index].q,
                       in: Double(MobileEQ.qualityRange.lowerBound)...Double(MobileEQ.qualityRange.upperBound), step: 0.05,
                       onEditingChanged: onEditingChanged)
            }
        }
    }

    private func logFrequency(for index: Int) -> Binding<Double> {
        Binding(get: { log10(settings.bands[index].frequency) }, set: { value in
            let range = MobileEQ.frequencyRange
            settings.bands[index].frequency = min(max(pow(10, value), Double(range.lowerBound)), Double(range.upperBound))
        })
    }

    private func moveBand(_ index: Int, _ frequency: Double, _ gain: Float) {
        var band = settings.bands[index]
        guard band.enabled, band.frequency != frequency || band.gain != gain else { return }
        band.frequency = frequency
        band.gain = gain
        settings.bands[index] = band
    }

    private func frequencyLabel(_ band: EQBand) -> String {
        "\(band.frequency.formatted(.number.precision(.fractionLength(0)))) Hz"
    }

    private func sliderRow(_ label: String, id: String, value: String, @ViewBuilder slider: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            slider().accessibilityLabel(label).accessibilityValue(value).accessibilityIdentifier(id)
        }
    }
}
