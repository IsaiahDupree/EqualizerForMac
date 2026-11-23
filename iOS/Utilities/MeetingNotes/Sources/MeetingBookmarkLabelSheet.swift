import SwiftUI

struct MeetingBookmarkLabelSheet: View {
    let draft: MeetingBookmarkDraft
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String

    init(draft: MeetingBookmarkDraft, onSave: @escaping (String) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _title = State(initialValue: draft.suggestedTitle)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add a short label so you can recognize this part of the recording later.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.secondary)

                TextField("Moment name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)

                Label("Recording position: \(timestamp(draft.time))", systemImage: "waveform")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Bookmark moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func timestamp(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
