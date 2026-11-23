import SwiftUI

struct MeetingDetailView: View {
    @Environment(MeetingNotesStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var transcriptDraft = ""
    @State private var summaryDraft = ""
    @State private var summaryTranscriptSnapshot = ""
    @State private var isEditingTranscript = false
    @State private var isEditingSummary = false
    @State private var isGeneratingSummary = false
    @State private var summaryGenerationTask: Task<Void, Never>?
    @State private var onDeviceLocales: [Locale] = []
    @State private var confirmDelete = false
    @AppStorage("clearRecord.transcriptionLocaleIdentifier") private var transcriptionLocaleIdentifier = "en-US"

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
                        if let summary = session.aiSummary {
                            ShareLink(item: summary) {
                                Label("Share saved summary", systemImage: "text.quote")
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
        .task {
            onDeviceLocales = OnDeviceTranscriber.onDeviceLocales
            if !onDeviceLocales.contains(where: { $0.identifier == transcriptionLocaleIdentifier }) {
                transcriptionLocaleIdentifier = onDeviceLocales.first?.identifier ?? "en-US"
            }
        }
        .onAppear {
            title = session?.title ?? ""
            transcriptDraft = session?.transcript ?? ""
            summaryDraft = session?.aiSummary ?? ""
            summaryTranscriptSnapshot = session?.transcript ?? ""
        }
        .onChange(of: title) { _, value in
            guard let session else { return }
            store.rename(session, to: value)
        }
        .onChange(of: session?.transcript) { _, value in
            if !isEditingTranscript { transcriptDraft = value ?? "" }
            summaryDraft = session?.aiSummary ?? ""
            summaryTranscriptSnapshot = value ?? ""
            isEditingSummary = false
        }
        .onDisappear {
            summaryGenerationTask?.cancel()
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
                        if onDeviceLocales.isEmpty {
                            Text("No on-device transcription language is currently available. You can still keep and share the recording.")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.orange.opacity(0.9))
                        } else {
                            Picker("Transcription language", selection: $transcriptionLocaleIdentifier) {
                                ForEach(onDeviceLocales, id: \.identifier) { locale in
                                    Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                                        .tag(locale.identifier)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.cyan)
                            .accessibilityIdentifier("transcriptionLanguagePicker")
                        }
                        Button {
                            Task {
                                await store.transcribe(
                                    session,
                                    localeIdentifier: transcriptionLocaleIdentifier
                                )
                            }
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
                        .disabled(store.transcribingID != nil || onDeviceLocales.isEmpty)
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
                                .disabled(isEditingSummary || isGeneratingSummary)
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

                if !session.transcript.isEmpty {
                    summaryCard(session)
                }

                Label("Audio file stored in this app's protected local folder.", systemImage: "lock.fill")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(20)
        }
    }

    private func summaryCard(_ session: MeetingSession) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("ON-DEVICE MEETING SUMMARY", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.cyan)
                Spacer()
                if let savedSummary = session.aiSummary, !isEditingSummary {
                    ShareLink(item: savedSummary) {
                        Image(systemName: "square.and.arrow.up").foregroundStyle(.cyan)
                    }
                }
            }

            if let savedSummary = session.aiSummary, !isEditingSummary {
                Text(savedSummary)
                    .font(.system(size: 14, design: .rounded))
                    .lineSpacing(4)
                    .foregroundStyle(.white.opacity(0.88))
                    .textSelection(.enabled)

                if !store.summaryIsCurrent(for: session) {
                    Label("The transcript changed after this summary was saved.", systemImage: "exclamationmark.circle")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.orange.opacity(0.9))
                }

                HStack(spacing: 12) {
                    Button("Edit") {
                        summaryDraft = savedSummary
                        summaryTranscriptSnapshot = session.transcript
                        isEditingSummary = true
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.cyan)
                    .disabled(isEditingTranscript || isGeneratingSummary)
                    Button("Remove summary", role: .destructive) {
                        if store.clearSummary(session.id) { summaryDraft = "" }
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .disabled(isEditingTranscript || isGeneratingSummary)
                }
            } else if isEditingSummary {
                Text("Review names, decisions, action items, and dates. The model can make mistakes.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                TextEditor(text: $summaryDraft)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 210)
                    .padding(9)
                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Button("Cancel") {
                        summaryDraft = session.aiSummary ?? ""
                        summaryTranscriptSnapshot = session.transcript
                        isEditingSummary = false
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button {
                        if store.updateSummary(
                            session.id,
                            to: summaryDraft,
                            basedOn: summaryTranscriptSnapshot
                        ) {
                            summaryDraft = summaryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            isEditingSummary = false
                        }
                    } label: {
                        Label("Save reviewed summary", systemImage: "checkmark")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.cyan, in: Capsule())
                    }
                }
            } else {
                Text("Draft a short summary, decisions, action items, and open questions from the saved transcript.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))
            }

            Button {
                summaryGenerationTask = Task { await createSummary(for: session) }
            } label: {
                HStack {
                    if isGeneratingSummary { ProgressView().tint(.black) }
                    else { Image(systemName: "sparkles") }
                    Text(isGeneratingSummary
                         ? (session.transcript.count > 6_000 ? "Summarizing sections on this device…" : "Drafting on this device…")
                         : (session.aiSummary == nil ? "Create editable draft" : "Refresh draft"))
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.black)
                .background(Color.cyan, in: RoundedRectangle(cornerRadius: 13))
            }
            .disabled(
                !FoundationModelsMeetingSummarizer.isAvailable
                    || isGeneratingSummary
                    || isEditingTranscript
                    || isEditingSummary
                    || store.transcribingID == session.id
            )
            .opacity(FoundationModelsMeetingSummarizer.isAvailable ? 1 : 0.48)

            if isGeneratingSummary {
                Button("Cancel local draft", role: .cancel) {
                    summaryGenerationTask?.cancel()
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .center)
            }

            if session.transcript.count > 6_000 {
                Text("Long transcripts are summarized in local sections and combined. Review names, decisions, and action items before sharing.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
            }

            if !FoundationModelsMeetingSummarizer.isAvailable {
                Text(FoundationModelsMeetingSummarizer.unavailableMessage)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
            }

            Text("The draft uses only this saved transcript and stays local until you choose to share it.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.43))
        }
        .padding(17)
        .background(Color(red: 0.105, green: 0.12, blue: 0.16), in: RoundedRectangle(cornerRadius: 18))
    }

    @MainActor
    private func createSummary(for session: MeetingSession) async {
        guard !isGeneratingSummary, !isEditingTranscript, !isEditingSummary else { return }
        isGeneratingSummary = true
        let transcriptSnapshot = session.transcript
        summaryTranscriptSnapshot = transcriptSnapshot
        defer {
            isGeneratingSummary = false
            summaryGenerationTask = nil
        }
        do {
            let draft = try await FoundationModelsMeetingSummarizer.summarize(transcript: transcriptSnapshot)
            try Task.checkCancellation()
            guard store.sessions.first(where: { $0.id == session.id })?.transcript == transcriptSnapshot else {
                store.errorMessage = "The transcript changed while the summary was being prepared. Generate a fresh draft."
                return
            }
            summaryDraft = draft
            isEditingSummary = true
        } catch is CancellationError {
            // Cancellation leaves the saved transcript and any existing summary unchanged.
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    }
}
