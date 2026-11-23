import AVFAudio
import Foundation
import Observation
import Speech

@MainActor @Observable
final class MeetingNotesStore {
    private(set) var sessions: [MeetingSession] = []
    private(set) var isRecording = false
    private(set) var recordingSeconds = 0
    private(set) var transcribingID: UUID?
    var errorMessage: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingTimer: Timer?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    private var directory: URL {
        URL.applicationSupportDirectory.appending(path: "ClearRecord", directoryHint: .isDirectory)
    }

    private var indexURL: URL { directory.appending(path: "sessions.json") }

    init() {
        loadIndex()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.stopRecording()
                self.errorMessage = "Recording stopped because the microphone was interrupted. The saved portion is in your sessions."
            }
        }
    }

    func startRecording(consentConfirmed: Bool) async {
        guard consentConfirmed else {
            errorMessage = MeetingNotesError.consentRequired.localizedDescription
            return
        }

        let speechStatus = await OnDeviceTranscriber.authorization()
        guard speechStatus == .authorized else {
            errorMessage = MeetingNotesError.speechDenied.localizedDescription
            return
        }

        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        guard microphoneAllowed else {
            errorMessage = MeetingNotesError.microphoneDenied.localizedDescription
            return
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "\(UUID().uuidString).m4a")
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .spokenAudio)
            try audioSession.setActive(true)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.prepareToRecord()
            guard newRecorder.record() else { throw MeetingNotesError.recordingCouldNotStart }

            recorder = newRecorder
            recordingSeconds = 0
            isRecording = true
            errorMessage = nil
            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.recordingSeconds += 1
                    if self.recordingSeconds >= 7_200 { self.stopRecording() }
                }
            }
        } catch {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        guard let recorder else { return }
        let duration = recorder.currentTime
        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        do {
            let fileValues = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = fileValues.fileSize, size > 0 else { throw MeetingNotesError.recordingCouldNotStart }
            let now = Date()
            let session = MeetingSession(
                id: UUID(),
                title: "Meeting · \(now.formatted(date: .abbreviated, time: .shortened))",
                createdAt: now,
                duration: duration,
                audioFileName: url.lastPathComponent,
                transcript: ""
            )
            sessions.insert(session, at: 0)
            try saveIndex()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func transcribe(_ session: MeetingSession) async {
        guard transcribingID == nil else { return }
        transcribingID = session.id
        errorMessage = nil
        do {
            let transcript = try await OnDeviceTranscriber.transcribe(fileURL: audioURL(for: session))
            guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
            sessions[index].transcript = transcript
            try saveIndex()
        } catch {
            errorMessage = error.localizedDescription
        }
        transcribingID = nil
    }

    func rename(_ session: MeetingSession, to title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        sessions[index].title = value
        do { try saveIndex() } catch { errorMessage = error.localizedDescription }
    }

    func remove(_ session: MeetingSession) {
        do {
            let audio = audioURL(for: session)
            if FileManager.default.fileExists(atPath: audio.path) { try FileManager.default.removeItem(at: audio) }
            sessions.removeAll { $0.id == session.id }
            try saveIndex()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func shareAudioURL(for session: MeetingSession) -> URL {
        audioURL(for: session)
    }

    func audioURL(for session: MeetingSession) -> URL {
        directory.appending(path: session.audioFileName)
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let loaded = try? JSONDecoder().decode([MeetingSession].self, from: data) else { return }
        sessions = loaded.filter { FileManager.default.fileExists(atPath: audioURL(for: $0).path) }
    }

    private func saveIndex() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(sessions)
        try data.write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
