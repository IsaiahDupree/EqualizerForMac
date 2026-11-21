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
    var onPresetLibrary: (() -> Void)?
    var comparison: EqualizerComparison?

    private var listeningToReference: Bool { comparison?.listeningToReference == true }

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
                         interaction: listeningToReference ? nil :
                            .init(select: { selectedBand = $0 }, move: moveBand, editingChanged: onEditingChanged))
            if let comparison { comparison }
            Toggle("Bypass EQ", isOn: $settings.bypassed)
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("bypassEQ")
                .disabled(listeningToReference)
            bandControls
                .disabled(listeningToReference)
        }
    }

    private var presets: some View {
        Menu {
            if let onPresetLibrary {
                Button("Preset Library", systemImage: "folder", action: onPresetLibrary)
                Divider()
            }
            ForEach(Presets.all, id: \.name) { preset in
                Button(preset.name) {
                    comparison?.audition(false)
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
            filterDetails(selectedBand)
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
                            .foregroundStyle(selected ? Self.accent : band.enabled ? .primary : .secondary)
                .background(selected ? Self.accent.opacity(0.13) : Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Band \(index + 1), \(frequencyLabel(band))\(band.enabled ? "" : ", disabled")")
        .accessibilityIdentifier("eqBand\(index)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func bandSliders(_ index: Int) -> some View {
        let band = settings.bands[index]
        return VStack(spacing: 10) {
            sliderRow("Frequency", id: "eqFrequency", value: frequencyLabel(band)) {
                Slider(value: logFrequency(for: index), in: log10(20)...log10(20_000), onEditingChanged: onEditingChanged)
            }
            if band.type.usesGain {
                sliderRow("Gain", id: "eqGain", value: "\(band.gainLabel) dB") {
                    Slider(value: $settings.bands[index].gain, in: MobileEQ.gainRange, step: 0.5,
                           onEditingChanged: onEditingChanged)
                }
            }
            if band.type.supportsSlope {
                Picker("Slope", selection: $settings.bands[index].slopeDbPerOct) {
                    ForEach(FilterDesigner.slopes, id: \.self) { slope in
                        Text("\(Int(slope)) dB/oct").tag(slope)
                    }
                }
            } else {
                sliderRow("Width (Q)", id: "eqQuality", value: band.q.formatted(.number.precision(.fractionLength(2)))) {
                    Slider(value: $settings.bands[index].q,
                           in: Double(MobileEQ.qualityRange.lowerBound)...Double(MobileEQ.qualityRange.upperBound), step: 0.05,
                           onEditingChanged: onEditingChanged)
                }
            }
        }
    }

    private func filterDetails(_ index: Int) -> some View {
        DisclosureGroup {
            Picker("Shape", selection: $settings.bands[index].type) {
                ForEach(MobileEQ.filterTypes) { type in Text(type.mobileName).tag(type) }
            }
            Toggle("Filter Enabled", isOn: $settings.bands[index].enabled)
        } label: {
            HStack {
                Text("Filter Details").font(.subheadline.weight(.medium))
                Spacer()
                Text(settings.bands[index].type.mobileName)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.trailing, 6)
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
        if band.type.usesGain { band.gain = gain }
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

struct EqualizerComparison: View {
    let hasReference: Bool
    let listeningToReference: Bool
    let capture: () -> Void
    let audition: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("A/B Compare").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button(hasReference ? "Update A" : "Set A", action: capture)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 36)
                    .disabled(listeningToReference)
                    .accessibilityIdentifier("setComparisonReference")
            }
            HStack(spacing: 6) {
                option("A · Reference", reference: true).disabled(!hasReference)
                option("B · Edited", reference: false)
            }
        }
    }

    private func option(_ title: String, reference: Bool) -> some View {
        let selected = listeningToReference == reference
        return Button {
            audition(reference)
        } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected ? EqualizerEditor.accent : .secondary)
                .background(selected ? EqualizerEditor.accent.opacity(0.12) : .primary.opacity(0.055),
                            in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(reference ? "comparisonA" : "comparisonB")
    }
}
