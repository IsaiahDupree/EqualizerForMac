import SwiftUI

struct MeetingDetailView: View {
    @Environment(MeetingNotesStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var transcriptDraft = ""
    @State private var isEditingTranscript = false
    @State private var confirmDelete = false

    let sessionID: UUID

    private var session: MeetingSession? { store.sessions.first { $0.id == sessionID } }

    var body: some View {
        Group {
            if let session {
                detail(session)
            } else {
                ContentUnavailableView("Recording not found", systemImage: "waveform.slash")
            }
        }
        .background(Color(red: 0.055, green: 0.065, blue: 0.09).ignoresSafeArea())
        .navigationTitle("Session notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let session {
                        ShareLink(item: store.shareAudioURL(for: session)) {
                            Label("Share audio file", systemImage: "waveform")
                        }
                        if !session.transcript.isEmpty && !isEditingTranscript {
                            ShareLink(item: session.transcript) {
                                Label("Share transcript", systemImage: "text.alignleft")
                            }
                        }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete recording and notes", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Delete this recording and its transcript?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete local recording", role: .destructive) {
                if let session { store.remove(session) }
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes only this app's audio file and saved transcript.")
        }
        .alert("Clear Record", isPresented: errorPresented) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "The requested action could not be completed.")
        }
        .onAppear {
            title = session?.title ?? ""
            transcriptDraft = session?.transcript ?? ""
        }
        .onChange(of: title) { _, value in
            guard let session else { return }
            store.rename(session, to: value)
        }
        .onChange(of: session?.transcript) { _, value in
            if !isEditingTranscript { transcriptDraft = value ?? "" }
        }
    }

    @ViewBuilder
    private func detail(_ session: MeetingSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SESSION TITLE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.45))
                    TextField("Meeting title", text: $title)
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .submitLabel(.done)
                    Text("\(session.createdAt.formatted(date: .long, time: .shortened)) · \(Int(session.duration / 60)) minutes")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }

                if session.transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 13) {
                        Label("ON DEVICE", systemImage: "iphone.and.lock")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(.cyan)
                        Text("Create a transcript from the saved recording. Recognition stays on this device.")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                        Button {
                            Task { await store.transcribe(session) }
                        } label: {
                            HStack {
                                if store.transcribingID == session.id { ProgressView().tint(.black) }
                                else { Image(systemName: "text.badge.plus") }
                                Text(store.transcribingID == session.id ? "Transcribing…" : "Transcribe on this device")
                            }
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.black)
                            .background(Color.cyan, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(store.transcribingID != nil)
                    }
                    .padding(17)
                    .background(Color(red: 0.105, green: 0.12, blue: 0.16), in: RoundedRectangle(cornerRadius: 18))
                } else {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Label("TRANSCRIPT", systemImage: "text.alignleft")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(1.4)
                                .foregroundStyle(.cyan)
                            Spacer()
                            if !isEditingTranscript {
                                ShareLink(item: session.transcript) {
                                    Image(systemName: "square.and.arrow.up").foregroundStyle(.cyan)
                                }
                                Button("Edit") {
                                    transcriptDraft = session.transcript
                                    isEditingTranscript = true
                                }
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.cyan)
                            }
                        }
                        if isEditingTranscript {
                            TextEditor(text: $transcriptDraft)
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 260)
                                .padding(9)
                                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                            HStack(spacing: 10) {
                                Button("Cancel") {
                                    transcriptDraft = session.transcript
                                    isEditingTranscript = false
                                }
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.7))
                                Spacer()
                                Button {
                                    if store.updateTranscript(session, to: transcriptDraft) {
                                        transcriptDraft = transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                        isEditingTranscript = false
                                    }
                                } label: {
                                    Label("Save corrections", systemImage: "checkmark")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 9)
                                        .background(Color.cyan, in: Capsule())
                                }
                            }
                        } else {
                            Text(session.transcript)
                                .font(.system(size: 15, design: .rounded))
                                .lineSpacing(5)
                                .foregroundStyle(.white.opacity(0.88))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(17)
                    .background(Color(red: 0.105, green: 0.12, blue: 0.16), in: RoundedRectangle(cornerRadius: 18))
                }

                Label("Audio file stored in this app's protected local folder.", systemImage: "lock.fill")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(20)
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    }
}
