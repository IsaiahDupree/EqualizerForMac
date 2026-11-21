import SwiftUI

struct OutputCorrectionView: View {
    let session: EqualizerSession
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                if let output = session.player.currentOutput {
                    Section {
                        Label(output.name, systemImage: "speaker.wave.2")
                    } header: {
                        Text("Current Output")
                    }
                    correctionSection(for: output)
                } else {
                    Section("Current Output") {
                        Text("Connect one audio output to assign a correction.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let message = message ?? session.storageMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Output Correction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { session.player.refreshOutput() }
    }

    private func correctionSection(for output: PlaybackOutput) -> some View {
        let correction = session.correction(for: output)
        let presets = session.presets.entries
        return Section {
            Menu {
                ForEach(presets) { preset in
                    Button(preset.file.name) {
                        do {
                            update(try OutputCorrection(preset: preset), for: output)
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
            } label: {
                LabeledContent("Preset") {
                    Label(correction?.name ?? "Choose", systemImage: "chevron.up.chevron.down")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(EqualizerEditor.accent)
                }
            }
            .disabled(presets.isEmpty)
            .accessibilityLabel("Correction preset")
            .accessibilityValue(correction?.name ?? "Choose")
            .accessibilityIdentifier("correctionPreset")

            if let correction {
                Toggle("Apply Correction", isOn: Binding(
                    get: { session.correction(for: output)?.enabled ?? false },
                    set: { enabled in
                        var updated = correction
                        updated.enabled = enabled
                        update(updated, for: output)
                    }
                ))
                .accessibilityIdentifier("applyOutputCorrection")

                Button("Clear Assignment", role: .destructive) { update(nil, for: output) }
            }
        } header: {
            Text("Correction")
        } footer: {
            if presets.isEmpty {
                Text("Save a preset or import an AutoEq text file in the Preset Library to assign it here.")
            } else {
                Text("This preset follows the current output and runs after your EQ for audio played in Sonance.")
            }
        }
    }

    private func update(_ correction: OutputCorrection?, for output: PlaybackOutput) {
        message = session.setCorrection(correction, for: output) ? nil : "The audio output changed. Choose a preset for the current output."
    }
}
