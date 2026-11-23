import SwiftUI

struct MeetingLibraryView: View {
    @Environment(MeetingNotesStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var consentConfirmed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    if let error = store.errorMessage { errorCard(error) }
                    recordingCard
                    sessionList
                    privacyNote
                }
                .padding(20)
                .padding(.bottom, 36)
            }
            .background(Color(red: 0.055, green: 0.065, blue: 0.09).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: scenePhase) { _, phase in
                if phase != .active && store.isRecording {
                    store.stopRecording()
                    store.errorMessage = "Recording stopped when Clear Record left the foreground. The saved portion is in your sessions."
                }
            }
            .onChange(of: store.isRecording) { _, isRecording in
                if isRecording { consentConfirmed = false }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CLEAR RECORD")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(.cyan)
                    Text("Meetings,\nkept clear.")
                        .font(.system(size: 35, weight: .bold, design: .rounded))
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 31, weight: .medium))
                    .foregroundStyle(.cyan)
                    .frame(width: 72, height: 72)
                    .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 23))
            }
            Text("Record a conversation with everyone's agreement. Transcription is optional and requested only when you choose it.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(21)
        .background(
            LinearGradient(colors: [Color(red: 0.10, green: 0.17, blue: 0.24), Color(red: 0.085, green: 0.11, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 27)
        )
        .overlay(RoundedRectangle(cornerRadius: 27).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.isRecording {
                HStack(spacing: 11) {
                    Circle().fill(.red).frame(width: 11, height: 11)
                    Text("RECORDING")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(.red)
                    Spacer()
                    Text(durationString(store.recordingSeconds))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                Text("The microphone is active. Stop when the session ends.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                Button(action: store.stopRecording) {
                    Label("Stop and save", systemImage: "stop.fill")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(.white)
                        .background(.red, in: RoundedRectangle(cornerRadius: 15))
                }
            } else {
                Toggle(isOn: $consentConfirmed) {
                    Text("Everyone whose voice will be recorded has agreed.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(.cyan)

                Button {
                    Task { await store.startRecording(consentConfirmed: consentConfirmed) }
                } label: {
                    Group {
                        if store.isStartingRecording {
                            HStack { ProgressView().tint(.black); Text("Starting…") }
                        } else {
                            Label("Start recording", systemImage: "record.circle")
                        }
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(Color(red: 0.03, green: 0.10, blue: 0.13))
                    .background(consentConfirmed && !store.isStartingRecording ? Color.cyan : Color.gray.opacity(0.35), in: RoundedRectangle(cornerRadius: 15))
                }
                .disabled(!consentConfirmed || store.isStartingRecording)
                .accessibilityIdentifier("startRecording")
                Text("You can stop at any time. Speech access is requested only if you later choose on-device transcription. Recording is limited to two hours.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
            }
        }
        .padding(18)
        .background(Color(red: 0.105, green: 0.12, blue: 0.16), in: RoundedRectangle(cornerRadius: 21))
        .overlay(RoundedRectangle(cornerRadius: 21).stroke(.white.opacity(0.07), lineWidth: 1))
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SAVED SESSIONS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("\(store.sessions.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.cyan)
            }

            if store.sessions.isEmpty {
                ContentUnavailableView("No recordings yet", systemImage: "waveform", description: Text("After a session, find its audio and on-device transcript here."))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 8)
            } else {
                ForEach(store.sessions) { session in
                    NavigationLink {
                        MeetingDetailView(sessionID: session.id)
                    } label: {
                        SessionRow(session: session, isTranscribing: store.transcribingID == session.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var privacyNote: some View {
        Label("Audio stays in this app. Transcription requires on-device recognition and never falls back to network processing.", systemImage: "lock.shield")
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(.white.opacity(0.47))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(message).font(.system(size: 13, design: .rounded)).foregroundStyle(.white.opacity(0.82))
            Spacer(minLength: 0)
            Button { store.errorMessage = nil } label: { Image(systemName: "xmark").foregroundStyle(.white.opacity(0.5)) }
        }
        .padding(14)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private func durationString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct SessionRow: View {
    let session: MeetingSession
    let isTranscribing: Bool

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 45, height: 45)
                .background(.cyan.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                Text("\(session.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(Int(session.duration / 60)) min")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.48))
            }
            Spacer(minLength: 0)
            if isTranscribing { ProgressView().tint(.cyan) }
            else { Image(systemName: session.transcript.isEmpty ? "text.badge.plus" : "text.alignleft").foregroundStyle(.cyan.opacity(0.8)) }
        }
        .padding(13)
        .background(Color(red: 0.105, green: 0.12, blue: 0.16), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.06), lineWidth: 1))
    }
}
