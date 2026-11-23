import SwiftUI

struct SpeechListeningView: View {
    let session: EqualizerSession
    @Environment(\.dismiss) private var dismiss
    @State private var bassImpact = 0
    @State private var vocalPosition = 0
    @State private var trebleComfort = 0
    @State private var profileName = "My Headphones"
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose a starting sound, then adjust the equalizer to suit the recording and your headphones. This replaces your current EQ; save it first if you want to keep it.")
                        .foregroundStyle(.secondary)
                    ForEach(SpeechListening.allCases) { profile in
                        Button {
                            session.applySpeechListening(profile)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.title).font(.headline)
                                Text(profile.description).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Speech Listening")
                } footer: {
                    Text("These EQ curves change tone; they do not isolate voices or remove background noise. They apply to audio played in Sonance. Other apps require a compatible AUv3 host.")
                }
                Section {
                    Text("Describe the sound you prefer. Sonance builds an editable starting curve from these choices; it does not measure your headphones or identify their model.")
                        .foregroundStyle(.secondary)

                    TextField("Profile name", text: $profileName)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("headphoneProfileName")

                    preferencePicker("Bass impact", selection: $bassImpact,
                                     options: [(-1, "Less"), (0, "Balanced"), (1, "More")])
                    preferencePicker("Vocal position", selection: $vocalPosition,
                                     options: [(-1, "Relaxed"), (0, "Balanced"), (1, "Forward")])
                    preferencePicker("Treble comfort", selection: $trebleComfort,
                                     options: [(1, "Brighter"), (0, "Balanced"), (-1, "Softer")])

                    VStack(alignment: .leading, spacing: 9) {
                        Text("Suggested Curve")
                            .font(.subheadline.weight(.medium))
                        ResponsePlot(
                            bands: suggestedSettings.bands,
                            sampleRate: 48_000,
                            selection: nil,
                            bypassed: false
                        )
                        .accessibilityLabel("Suggested headphone profile frequency response")
                        .accessibilityIdentifier("headphoneProfilePreview")
                        Text("Suggested preamp: \(suggestedSettings.preamp.formatted(.number.precision(.fractionLength(1)))) dB")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)

                    Button("Save Profile to Presets", systemImage: "bookmark") {
                        saveProfile()
                    }
                    .accessibilityIdentifier("saveHeadphoneProfile")

                    Button("Apply & Compare in Player", systemImage: "arrow.left.arrow.right") {
                        applyAndCompare()
                    }
                    .accessibilityIdentifier("applyHeadphoneProfile")
                } header: {
                    Text("Headphone Profile Assistant")
                } footer: {
                    Text("The suggestion is a listening preference starting point, not a measured correction for a headphone model. Apply it to Sonance's file player, then use A/B Compare to hear it against your current curve.")
                }
            }
            .navigationTitle("Listening & Sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .alert("Headphone Profile", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func preferencePicker(_ title: String, selection: Binding<Int>, options: [(Int, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            Picker(title, selection: selection) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].1).tag(options[index].0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private var suggestedSettings: MobileEQSettings {
        let bass = [-3, -2, -1, 0, 0, 0, 0, 0, 0, 0].map { Float($0 * bassImpact) }
        let vocals = [0, 0, 0, 1, 2, 3, 2, 0, 0, 0].map { Float($0 * vocalPosition) }
        let treble = [0, 0, 0, 0, 0, 1, 2, 3, 2, 1].map { Float($0 * trebleComfort) }
        let gains = bass.indices.map { bass[$0] + vocals[$0] + treble[$0] }
        let bands = Presets.graphic(gains: gains)
        let peakDb = FrequencyResponse.curve(bands: bands, sampleRate: 48_000, points: 512)
            .map { $0.db }
            .max() ?? 0
        let preamp = peakDb > 0 ? -Float(ceil(peakDb + 1)) : 0
        return MobileEQSettings(bands: bands, preamp: preamp, bypassed: false)
    }

    private func saveProfile() {
        do {
            try session.presets.save(suggestedSettings, name: profileName)
            message = "Saved \(try PresetLibrary.validName(profileName)) to your preset library."
        } catch {
            message = error.localizedDescription
        }
    }

    private func applyAndCompare() {
        session.captureReference()
        session.editingChanged(true)
        session.updateEQ { $0 = suggestedSettings }
        session.selectBand(suggestedSettings.bands.firstIndex(where: \.enabled))
        session.editingChanged(false)
        dismiss()
    }
}
