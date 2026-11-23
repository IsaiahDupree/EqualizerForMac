import SwiftUI

struct MeetingSummaryReviewView: View {
    @Environment(MeetingNotesStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editedSummary: String

    let draft: MeetingSummaryDraft

    init(draft: MeetingSummaryDraft) {
        self.draft = draft
        _editedSummary = State(initialValue: draft.summary)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("UNSAVED ON-DEVICE DRAFT", systemImage: "lock.shield")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(.cyan)

                    Text(draft.sessionTitle)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Review names, decisions, owners, and dates. Nothing is saved until you choose Save.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: $editedSummary)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 260)
                        .padding(10)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Editable meeting summary draft")

                    if let error = store.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("This draft was prepared from the saved transcript. If that transcript has changed, Clear Record will refuse to attach this draft to it.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(Color(red: 0.055, green: 0.065, blue: 0.09).ignoresSafeArea())
            .navigationTitle("Review summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        store.discardPendingShortcutSummaryDraft()
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.75))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.savePendingShortcutSummaryDraft(editedSummary) {
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.cyan)
                    .disabled(editedSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }
}
