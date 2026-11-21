import SwiftUI

struct SpeechListeningView: View {
    let session: EqualizerSession
    @Environment(\.dismiss) private var dismiss

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
            }
            .navigationTitle("Listening Modes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
