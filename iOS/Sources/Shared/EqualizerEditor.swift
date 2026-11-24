import SwiftUI

struct EqualizerEditor: View {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.58, green: 0.71, blue: 1, alpha: 1)
            : UIColor(red: 0.12, green: 0.35, blue: 0.83, alpha: 1)
    })

    @Binding var settings: MobileEQSettings
    @Binding var selectedBand: Int?
    @State private var editingSide = false
    let sampleRate: Double
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onPresetLibrary: (() -> Void)?
    var onHeadphoneCatalog: (() -> Void)?
    var comparison: EqualizerComparison?

    private var listeningToReference: Bool { comparison?.listeningToReference == true }
    private var editingBands: [EQBand] {
        get { editingSide && settings.midSideEnabled ? settings.sideBands : settings.bands }
        nonmutating set {
            if editingSide && settings.midSideEnabled { settings.sideBands = newValue } else { settings.bands = newValue }
        }
    }
    private var selection: Int? { editingBands.isEmpty ? nil : min(max(selectedBand ?? 0, 0), editingBands.count - 1) }
    private var currentBand: EQBand? { selection.map { editingBands[$0] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Equalizer")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                presets
            }
            HStack {
                Toggle("Mid-Side", isOn: $settings.midSideEnabled)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("midSideEQ")
                Spacer()
                if settings.midSideEnabled {
                    Picker("EQ curve", selection: $editingSide) {
                        Text("Mid").tag(false)
                        Text("Side").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    .accessibilityIdentifier("midSideCurvePicker")
                }
            }
            HStack {
                Toggle("Linear-Phase FIR", isOn: $settings.linearPhaseEnabled)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("linearPhaseEQ")
                Spacer()
                if settings.linearPhaseEnabled {
                    Text("About 21 ms latency at 48 kHz")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ResponsePlot(bands: editingBands, sampleRate: sampleRate, selection: currentBand?.id,
                         bypassed: settings.bypassed,
                         interaction: listeningToReference ? nil :
                            .init(select: selectBand, move: moveBand, editingChanged: onEditingChanged))
            if let comparison { comparison }
            Toggle("Bypass EQ", isOn: $settings.bypassed)
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("bypassEQ")
                .disabled(listeningToReference)
            bandControls
                .disabled(listeningToReference)
        }
        .onChange(of: settings.midSideEnabled) { _, enabled in
            if !enabled { editingSide = false }
        }
    }

    private var presets: some View {
        Menu {
            if let onPresetLibrary {
                Button("Preset Library", systemImage: "folder", action: onPresetLibrary)
                Divider()
            }
            if let onHeadphoneCatalog {
                Button("Headphone Correction Library", systemImage: "headphones", action: onHeadphoneCatalog)
                Divider()
            }
            ForEach(Presets.all, id: \.name) { preset in
                Button(preset.name) {
                    comparison?.audition(false)
                    applyPreset(MobileEQSettings.startingPoint(bands: preset.bands, sampleRate: sampleRate))
                }
            }
            Menu("Listening Presets") {
                ForEach(SoundStarterPreset.allCases) { profile in
                    Button(profile.title) {
                        comparison?.audition(false)
                        applyPreset(profile.makeSettings(sampleRate: sampleRate))
                    }
                }
            }
            Menu("Speech Listening") {
                ForEach(SpeechListening.allCases) { profile in
                    Button(profile.title) {
                        comparison?.audition(false)
                        applyPreset(profile.settings)
                    }
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
            HStack(spacing: 8) {
                bandPicker
                Button(role: .destructive, action: removeBand) {
                    Image(systemName: "minus")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .accessibilityLabel("Remove band")
                .accessibilityIdentifier("removeBand")
                .disabled(selection == nil)

                Button(action: addBand) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(Self.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Self.accent)
                .accessibilityLabel("Add band")
                .accessibilityIdentifier("addBand")
                .disabled(editingBands.count >= MobileEQ.maximumBandCount)
            }
            if let currentBand {
                bandSliders(currentBand)
                filterDetails(currentBand)
            }
            Divider()
            sliderRow("Preamp", id: "eqPreamp", value: "\(settings.preamp.formatted(.number.precision(.fractionLength(1)))) dB") {
                Slider(value: $settings.preamp, in: MobileEQ.preampRange, step: 0.5, onEditingChanged: onEditingChanged)
            }
            HStack(alignment: .center) {
                Button {
                    onEditingChanged(true)
                    settings = settings.applyingEstimatedHeadroom(sampleRate: sampleRate)
                    onEditingChanged(false)
                } label: {
                    Label("Auto Headroom", systemImage: "waveform.path")
                        .font(.subheadline.weight(.medium))
                }
                .accessibilityIdentifier("autoHeadroom")
                Spacer()
                Text("Response estimate; not a limiter")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var bandPicker: some View {
        let title = selection.map { bandTitle(editingBands[$0], index: $0) } ?? "No bands"
        return Menu {
            ForEach(Array(editingBands.enumerated()), id: \.element.id) { index, band in
                Button {
                    selectBand(band.id)
                } label: {
                    if index == selection {
                        Label(bandTitle(band, index: index), systemImage: "checkmark")
                    } else {
                        Text(bandTitle(band, index: index))
                    }
                }
                .accessibilityIdentifier("eqBand\(index)")
            }
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.monospacedDigit().weight(.semibold))
                    if let currentBand {
                        Text(currentBand.type.mobileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 9))
        }
        .accessibilityLabel("Filter band")
        .accessibilityValue(title)
        .accessibilityIdentifier("eqBandSelector")
        .disabled(editingBands.isEmpty)
    }

    private func bandTitle(_ band: EQBand, index: Int) -> String {
        "Band \(index + 1) · \(frequencyLabel(band))\(band.enabled ? "" : " · Off")"
    }

    private func selectBand(_ id: UUID) {
        if let index = editingBands.firstIndex(where: { $0.id == id }) {
            selectedBand = index
        }
    }

    private func addBand() {
        guard editingBands.count < MobileEQ.maximumBandCount else { return }
        changeBands {
            $0.append(MobileEQ.newBand())
            return $0.count - 1
        }
    }

    private func removeBand() {
        guard let index = selection else { return }
        changeBands {
            $0.remove(at: index)
            return $0.isEmpty ? nil : min(index, $0.count - 1)
        }
    }

    private func changeBands(_ edit: (inout [EQBand]) -> Int?) {
        var updated = editingBands
        let next = edit(&updated)
        onEditingChanged(true)
        editingBands = updated
        selectedBand = next
        onEditingChanged(false)
    }

    private func applyPreset(_ preset: MobileEQSettings) {
        onEditingChanged(true)
        settings = preset
        editingSide = false
        selectedBand = preset.bands.firstIndex(where: \.enabled)
        onEditingChanged(false)
    }

    private func bandSliders(_ band: EQBand) -> some View {
        VStack(spacing: 10) {
            sliderRow("Frequency", id: "eqFrequency", value: frequencyLabel(band)) {
                Slider(value: logFrequency(for: band), in: log10(20)...log10(20_000), onEditingChanged: onEditingChanged)
            }
            if band.type.usesGain {
                sliderRow("Gain", id: "eqGain", value: "\(band.gainLabel) dB") {
                    Slider(value: binding(\.gain, for: band), in: MobileEQ.gainRange, step: 0.5,
                           onEditingChanged: onEditingChanged)
                }
            }
            if band.type.supportsSlope {
                Picker("Slope", selection: binding(\.slopeDbPerOct, for: band)) {
                    ForEach(FilterDesigner.slopes, id: \.self) { slope in
                        Text("\(Int(slope)) dB/oct").tag(slope)
                    }
                }
            } else {
                sliderRow("Width (Q)", id: "eqQuality", value: band.q.formatted(.number.precision(.fractionLength(2)))) {
                    Slider(value: binding(\.q, for: band),
                           in: Double(MobileEQ.qualityRange.lowerBound)...Double(MobileEQ.qualityRange.upperBound), step: 0.05,
                           onEditingChanged: onEditingChanged)
                }
            }
        }
    }

    private func filterDetails(_ band: EQBand) -> some View {
        DisclosureGroup {
            Picker("Shape", selection: binding(\.type, for: band)) {
                ForEach(MobileEQ.filterTypes) { type in Text(type.mobileName).tag(type) }
            }
            Toggle("Filter Enabled", isOn: binding(\.enabled, for: band))
        } label: {
            HStack {
                Text("Filter Details").font(.subheadline.weight(.medium))
                Spacer()
                Text(band.type.mobileName)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.trailing, 6)
        }
    }

    private func binding<Value>(_ key: WritableKeyPath<EQBand, Value>, for band: EQBand) -> Binding<Value> {
        Binding(get: { editingBands.first(where: { $0.id == band.id })?[keyPath: key] ?? band[keyPath: key] },
                set: { value in
                    guard let index = editingBands.firstIndex(where: { $0.id == band.id }) else { return }
                    var updated = editingBands
                    updated[index][keyPath: key] = value
                    editingBands = updated
                })
    }

    private func logFrequency(for band: EQBand) -> Binding<Double> {
        let frequency = binding(\.frequency, for: band)
        return Binding(get: { log10(frequency.wrappedValue) }, set: { value in
            let range = MobileEQ.frequencyRange
            frequency.wrappedValue = min(max(pow(10, value), Double(range.lowerBound)), Double(range.upperBound))
        })
    }

    private func moveBand(_ id: UUID, _ frequency: Double, _ gain: Float) {
        guard let index = editingBands.firstIndex(where: { $0.id == id }) else { return }
        var band = editingBands[index]
        guard band.enabled, band.frequency != frequency || band.gain != gain else { return }
        band.frequency = frequency
        if band.type.usesGain { band.gain = gain }
        var updated = editingBands
        updated[index] = band
        editingBands = updated
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
