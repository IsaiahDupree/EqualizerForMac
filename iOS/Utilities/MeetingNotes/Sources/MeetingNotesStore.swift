import AVFAudio
import CryptoKit
import Foundation
import Observation
import Speech

@MainActor @Observable
final class MeetingNotesStore {
    static let shared = MeetingNotesStore()

    private(set) var sessions: [MeetingSession] = []
    private(set) var isRecording = false
    private(set) var isStartingRecording = false
    private(set) var recordingSeconds = 0
    private(set) var transcribingID: UUID?
    private(set) var summaryDraftingSessionID: UUID?
    private(set) var pendingShortcutSummaryDraft: MeetingSummaryDraft?
    private(set) var playbackSessionID: UUID?
    private(set) var playbackCurrentTime: TimeInterval = 0
    private(set) var playbackDuration: TimeInterval = 0
    private(set) var playbackRate: Float
    private(set) var isPlayingAudio = false
    var errorMessage: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingTimer: Timer?
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var playbackTimer: Timer?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    private var directory: URL {
        URL.applicationSupportDirectory.appending(path: "ClearRecord", directoryHint: .isDirectory)
    }

    private var indexURL: URL { directory.appending(path: "sessions.json") }
    private static let playbackRateDefaultsKey = "clearRecord.playbackRate"

    init() {
        let savedPlaybackRate = UserDefaults.standard.float(forKey: Self.playbackRateDefaultsKey)
        playbackRate = [0.75, 1, 1.25, 1.5, 2].contains(savedPlaybackRate) ? savedPlaybackRate : 1
        do {
            try prepareLocalDirectory()
        } catch {
            errorMessage = "Clear Record couldn't set its backup exclusion: \(error.localizedDescription)"
        }
        loadIndex()
        for session in sessions {
            do {
                try markExcludedFromBackup(at: audioURL(for: session))
            } catch {
                errorMessage = "A saved recording couldn't be marked for backup exclusion: \(error.localizedDescription)"
                break
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isRecording {
                    self.stopRecording()
                    self.errorMessage = "Recording stopped because the microphone was interrupted. The saved portion is in your sessions."
                } else {
                    self.pausePlayback()
                }
            }
        }
    }

    func startRecording(consentConfirmed: Bool) async {
        guard !isRecording, !isStartingRecording else { return }
        stopPlayback()
        isStartingRecording = true
        defer { isStartingRecording = false }

        guard consentConfirmed else {
            errorMessage = MeetingNotesError.consentRequired.localizedDescription
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
            try prepareLocalDirectory()
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
            var backupExclusionWarning: String?
            do {
                try markExcludedFromBackup(at: url)
            } catch {
                backupExclusionWarning = error.localizedDescription
            }
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
            do {
                try saveIndex()
            } catch {
                errorMessage = "The recording was created, but its session could not be saved to the library index: \(error.localizedDescription)"
                return
            }
            errorMessage = backupExclusionWarning.map {
                "Recording saved, but its backup exclusion couldn't be set: \($0)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func transcribe(_ session: MeetingSession, localeIdentifier: String) async {
        guard transcribingID == nil else { return }
        stopPlayback()
        transcribingID = session.id
        defer { transcribingID = nil }
        errorMessage = nil
        do {
            let locale = Locale(identifier: localeIdentifier)
            guard OnDeviceTranscriber.supportsOnDeviceRecognition(for: locale) else {
                throw MeetingNotesError.onDeviceRecognitionUnavailable
            }
            let speechStatus = await OnDeviceTranscriber.authorization()
            guard speechStatus == .authorized else { throw MeetingNotesError.speechDenied }
            let transcript = try await OnDeviceTranscriber.transcribe(
                fileURL: audioURL(for: session),
                locale: locale
            )
            guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
            let previous = sessions[index]
            sessions[index].transcript = transcript
            do {
                try saveIndex()
            } catch {
                sessions[index] = previous
                throw error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func updateTranscript(_ session: MeetingSession, to transcript: String) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return false }
        let previous = sessions[index]
        sessions[index].transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try saveIndex()
            errorMessage = nil
            return true
        } catch {
            sessions[index] = previous
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateSummary(_ sessionID: UUID, to summary: String, basedOn transcriptSnapshot: String) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return false }
        guard sessions[index].transcript == transcriptSnapshot else {
            errorMessage = "The transcript changed while the summary was being prepared. Generate a fresh draft."
            return false
        }
        let value = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            errorMessage = "A summary must contain text before it can be saved."
            return false
        }

        let previous = sessions[index]
        sessions[index].aiSummary = value
        sessions[index].summarySourceDigest = Self.digest(transcriptSnapshot)
        do {
            try saveIndex()
            errorMessage = nil
            return true
        } catch {
            sessions[index] = previous
            errorMessage = error.localizedDescription
            return false
        }
    }

    func summaryIsCurrent(for session: MeetingSession) -> Bool {
        guard let digest = session.summarySourceDigest else { return false }
        return digest == Self.digest(session.transcript)
    }

    func createSummaryDraft(for session: MeetingSession, transcriptSnapshot: String) async throws -> String {
        guard summaryDraftingSessionID == nil else {
            throw MeetingNotesError.summaryAlreadyInProgress
        }
        guard !isRecording, !isStartingRecording, transcribingID == nil else {
            throw MeetingNotesError.summaryAlreadyInProgress
        }
        guard sessions.contains(where: { $0.id == session.id }) else {
            throw MeetingNotesError.recordingNotFound
        }
        guard !transcriptSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeetingNotesError.summaryRequiresTranscript
        }
        guard sessions.first(where: { $0.id == session.id })?.transcript == transcriptSnapshot else {
            throw MeetingNotesError.summaryTranscriptChanged
        }

        summaryDraftingSessionID = session.id
        defer {
            if summaryDraftingSessionID == session.id { summaryDraftingSessionID = nil }
        }

        let draft = try await FoundationModelsMeetingSummarizer.summarize(transcript: transcriptSnapshot)
        try Task.checkCancellation()
        guard sessions.first(where: { $0.id == session.id })?.transcript == transcriptSnapshot else {
            throw MeetingNotesError.summaryTranscriptChanged
        }
        return draft
    }

    @discardableResult
    func stageShortcutSummaryDraft(for session: MeetingSession, transcriptSnapshot: String, summary: String) -> Bool {
        guard pendingShortcutSummaryDraft == nil else {
            errorMessage = MeetingNotesError.summaryReviewAlreadyOpen.localizedDescription
            return false
        }
        guard sessions.first(where: { $0.id == session.id })?.transcript == transcriptSnapshot else {
            errorMessage = MeetingNotesError.summaryTranscriptChanged.localizedDescription
            return false
        }
        pendingShortcutSummaryDraft = MeetingSummaryDraft(
            sessionID: session.id,
            sessionTitle: session.title,
            transcriptSnapshot: transcriptSnapshot,
            summary: summary
        )
        errorMessage = nil
        return true
    }

    @discardableResult
    func savePendingShortcutSummaryDraft(_ editedSummary: String) -> Bool {
        guard let draft = pendingShortcutSummaryDraft else { return false }
        guard updateSummary(
            draft.sessionID,
            to: editedSummary,
            basedOn: draft.transcriptSnapshot
        ) else { return false }
        pendingShortcutSummaryDraft = nil
        return true
    }

    func discardPendingShortcutSummaryDraft() {
        pendingShortcutSummaryDraft = nil
    }

    @discardableResult
    func clearSummary(_ sessionID: UUID) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return false }
        let previous = sessions[index]
        sessions[index].aiSummary = nil
        sessions[index].summarySourceDigest = nil
        do {
            try saveIndex()
            errorMessage = nil
            return true
        } catch {
            sessions[index] = previous
            errorMessage = error.localizedDescription
            return false
        }
    }

    func rename(_ session: MeetingSession, to title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let previous = sessions[index]
        sessions[index].title = value
        do {
            try saveIndex()
            errorMessage = nil
        } catch {
            sessions[index] = previous
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ session: MeetingSession) {
        if playbackSessionID == session.id { stopPlayback() }
        let previousSessions = sessions
        sessions.removeAll { $0.id == session.id }
        do {
            try saveIndex()
        } catch {
            sessions = previousSessions
            errorMessage = error.localizedDescription
            return
        }

        do {
            let audio = audioURL(for: session)
            if FileManager.default.fileExists(atPath: audio.path) {
                try FileManager.default.removeItem(at: audio)
            }
            errorMessage = nil
        } catch {
            errorMessage = "The session was removed from the library, but its private recording could not be deleted: \(error.localizedDescription)"
        }
    }

    func shareAudioURL(for session: MeetingSession) -> URL {
        audioURL(for: session)
    }

    func audioURL(for session: MeetingSession) -> URL {
        directory.appending(path: session.audioFileName)
    }

    func playbackTime(for sessionID: UUID) -> TimeInterval {
        playbackSessionID == sessionID ? playbackCurrentTime : 0
    }

    func togglePlayback(_ session: MeetingSession) {
        guard !isRecording, !isStartingRecording, transcribingID == nil else { return }
        if playbackSessionID == session.id {
            if isPlayingAudio {
                pausePlayback()
            } else {
                resumePlayback()
            }
            return
        }

        stopPlayback()
        do {
            let url = audioURL(for: session)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw MeetingNotesError.recordingNotFound
            }
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.rate = playbackRate
            guard player.prepareToPlay() else { throw MeetingNotesError.playbackCouldNotStart }

            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio)
            try audioSession.setActive(true)
            guard player.play() else { throw MeetingNotesError.playbackCouldNotStart }

            audioPlayer = player
            playbackSessionID = session.id
            playbackCurrentTime = 0
            playbackDuration = player.duration
            isPlayingAudio = true
            errorMessage = nil
            startPlaybackTimer()
        } catch {
            stopPlayback()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            errorMessage = error.localizedDescription
        }
    }

    func seekPlayback(to time: TimeInterval, in session: MeetingSession) {
        guard playbackSessionID == session.id, let audioPlayer else { return }
        let target = min(max(time, 0), max(audioPlayer.duration, 0))
        audioPlayer.currentTime = target
        playbackCurrentTime = target
        if target >= audioPlayer.duration, isPlayingAudio {
            pausePlayback()
        }
    }

    func setPlaybackRate(_ rate: Float) {
        let supportedRates: [Float] = [0.75, 1, 1.25, 1.5, 2]
        guard supportedRates.contains(rate) else { return }
        playbackRate = rate
        UserDefaults.standard.set(rate, forKey: Self.playbackRateDefaultsKey)
        if let audioPlayer, audioPlayer.enableRate { audioPlayer.rate = rate }
    }

    func stopPlayback(for sessionID: UUID? = nil) {
        if let sessionID, playbackSessionID != sessionID { return }
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        playbackSessionID = nil
        playbackCurrentTime = 0
        playbackDuration = 0
        isPlayingAudio = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func pausePlayback() {
        guard let audioPlayer, isPlayingAudio else { return }
        audioPlayer.pause()
        playbackCurrentTime = audioPlayer.currentTime
        isPlayingAudio = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func resumePlayback() {
        guard let audioPlayer, playbackSessionID != nil else { return }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio)
            try audioSession.setActive(true)
            if audioPlayer.currentTime >= audioPlayer.duration { audioPlayer.currentTime = 0 }
            guard audioPlayer.play() else { throw MeetingNotesError.playbackCouldNotStart }
            isPlayingAudio = true
            startPlaybackTimer()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            stopPlayback()
        }
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.audioPlayer else { return }
                self.playbackCurrentTime = player.currentTime
                if !player.isPlaying, self.isPlayingAudio {
                    if player.currentTime >= max(0, player.duration - 0.25) {
                        player.currentTime = player.duration
                        self.playbackCurrentTime = player.duration
                        self.isPlayingAudio = false
                        self.playbackTimer?.invalidate()
                        self.playbackTimer = nil
                        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    } else {
                        self.pausePlayback()
                    }
                }
            }
        }
    }

    private func loadIndex() {
        if FileManager.default.fileExists(atPath: indexURL.path) {
            do {
                try markExcludedFromBackup(at: indexURL)
            } catch {
                errorMessage = "The session index couldn't be marked for backup exclusion: \(error.localizedDescription)"
            }
        }
        guard let data = try? Data(contentsOf: indexURL),
              let loaded = try? JSONDecoder().decode([MeetingSession].self, from: data) else { return }
        sessions = loaded.filter { FileManager.default.fileExists(atPath: audioURL(for: $0).path) }
    }

    private func saveIndex() throws {
        try prepareLocalDirectory()
        let data = try JSONEncoder().encode(sessions)
        let existingIndex = FileManager.default.fileExists(atPath: indexURL.path)
        let previousData: Data?
        if existingIndex {
            previousData = try Data(contentsOf: indexURL)
        } else {
            previousData = nil
        }
        do {
            try data.write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try markExcludedFromBackup(at: indexURL)
        } catch {
            let saveError = error
            do {
                if let previousData {
                    try previousData.write(
                        to: indexURL,
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                    )
                    try markExcludedFromBackup(at: indexURL)
                } else if FileManager.default.fileExists(atPath: indexURL.path) {
                    try FileManager.default.removeItem(at: indexURL)
                }
            } catch {
                throw SessionIndexPersistenceError.rollbackFailed(
                    save: saveError.localizedDescription,
                    rollback: error.localizedDescription
                )
            }
            throw saveError
        }
    }

    private func prepareLocalDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try markExcludedFromBackup(at: directory)
    }

    private func markExcludedFromBackup(at url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var localURL = url
        try localURL.setResourceValues(values)
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private enum SessionIndexPersistenceError: LocalizedError {
    case rollbackFailed(save: String, rollback: String)

    var errorDescription: String? {
        switch self {
        case .rollbackFailed(let save, let rollback):
            "Clear Record could not save the session index (\(save)) or restore its previous contents (\(rollback)). The on-disk index may not match the previous state."
        }
    }
}
