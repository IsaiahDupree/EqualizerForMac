import AVFoundation
import Combine
import Foundation

@MainActor
final class TrackStudyStore: ObservableObject {
    static let shared = TrackStudyStore()

    @Published private(set) var track: PracticeTrack?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isImporting = false
    @Published private(set) var isAnalyzing = false
    @Published private(set) var activeLoopID: UUID?
    @Published var errorMessage: String?

    private let player = AVPlayer()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var periodicTimeObserver: Any?
    private var playbackRequested = false
    private var isWrappingLoop = false
    private var activeAnalysisID: UUID?
    private var activeAnalysisOperation: (any MusicAnalysisOperation)?

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        loadSavedTrack()
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard time.seconds.isFinite else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time.seconds
                self.isPlaying = self.player.timeControlStatus == .playing
                self.wrapPlaybackLoopIfNeeded(at: time.seconds)
                if time.seconds >= self.duration, self.activeLoopID == nil {
                    self.playbackRequested = false
                    self.isPlaying = false
                }
            }
        }
    }

    var duration: TimeInterval { track?.duration ?? 0 }

    func importTrack(from pickedURL: URL) async {
        guard !isImporting else { return }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        let didStartAccess = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { pickedURL.stopAccessingSecurityScopedResource() }
        }

        var copiedURL: URL?
        do {
            let identifier = UUID()
            let fileExtension = pickedURL.pathExtension.isEmpty ? "audio" : pickedURL.pathExtension
            let destination = try tracksDirectory().appendingPathComponent("\(identifier.uuidString).\(fileExtension)")
            try FileManager.default.copyItem(at: pickedURL, to: destination)
            copiedURL = destination

            let asset = AVURLAsset(url: destination)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else { throw TrackStudyError.invalidAudioFile }

            let imported = PracticeTrack(
                id: identifier,
                title: pickedURL.deletingPathExtension().lastPathComponent,
                storedFilename: destination.lastPathComponent,
                importedAt: .now,
                duration: duration,
                markers: [],
                analysis: nil
            )
            track = imported
            try saveTrack()
            playbackRequested = false
            isPlaying = false
            activeLoopID = nil
            player.replaceCurrentItem(with: AVPlayerItem(url: destination))
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
            currentTime = 0
            isPlaying = false
        } catch {
            if let copiedURL { try? FileManager.default.removeItem(at: copiedURL) }
            track = nil
            playbackRequested = false
            isPlaying = false
            activeLoopID = nil
            player.replaceCurrentItem(with: nil)
            errorMessage = error.localizedDescription
        }
    }

    func togglePlayback() {
        guard track != nil, player.currentItem != nil else { return }
        if playbackRequested {
            playbackRequested = false
            player.pause()
            isPlaying = false
        } else {
            if duration > 0, currentTime >= duration { seek(to: activeLoopStart ?? 0) }
            playbackRequested = true
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: TimeInterval) {
        guard duration > 0 else { return }
        var clamped = min(max(seconds, 0), duration)
        if let activeLoop,
           activeLoop.endSeconds > activeLoop.startSeconds {
            clamped = min(max(clamped, activeLoop.startSeconds), activeLoop.endSeconds - 0.05)
        }
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { _ in }
        currentTime = clamped
    }

    func addMarker(title: String, at position: TimeInterval? = nil) {
        guard var track else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let position = position ?? currentTime
        let marker = PracticeMarker(
            title: trimmed.isEmpty ? "Practice \(track.markers.count + 1)" : trimmed,
            seconds: min(max(position, 0), track.duration)
        )
        track.markers.append(marker)
        track.markers.sort { $0.seconds < $1.seconds }
        self.track = track
        persistOrReport()
    }

    func removeMarker(_ marker: PracticeMarker) {
        guard var track else { return }
        track.markers.removeAll { $0.id == marker.id }
        self.track = track
        persistOrReport()
    }

    func jumpToMarker(_ marker: PracticeMarker) {
        seek(to: marker.seconds)
    }

    func saveLoop(title: String, startSeconds: TimeInterval, endSeconds: TimeInterval) {
        errorMessage = nil
        guard var track else { return }
        guard startSeconds.isFinite, endSeconds.isFinite,
              startSeconds >= 0, endSeconds <= track.duration,
              endSeconds - startSeconds >= 0.5 else {
            errorMessage = "Set A and B at least half a second apart, with B after A."
            return
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let loop = PracticeLoop(
            title: trimmed.isEmpty ? "Loop \(track.loops.count + 1)" : trimmed,
            startSeconds: startSeconds,
            endSeconds: endSeconds
        )
        track.loops.append(loop)
        track.loops.sort { $0.startSeconds < $1.startSeconds }
        self.track = track
        persistOrReport()
    }

    func toggleLoopPlayback(_ loop: PracticeLoop) {
        guard track?.loops.contains(where: { $0.id == loop.id }) == true else { return }
        if activeLoopID == loop.id {
            activeLoopID = nil
        } else {
            activeLoopID = loop.id
            seek(to: loop.startSeconds)
        }
    }

    func removeLoop(_ loop: PracticeLoop) {
        guard var track else { return }
        track.loops.removeAll { $0.id == loop.id }
        if activeLoopID == loop.id { activeLoopID = nil }
        self.track = track
        persistOrReport()
    }

    func analyzeTrack() async {
        guard let sourceTrack = track, !isAnalyzing else { return }
        let analysisID = UUID()
        activeAnalysisID = analysisID
        isAnalyzing = true
        errorMessage = nil
        defer {
            if activeAnalysisID == analysisID {
                activeAnalysisID = nil
                activeAnalysisOperation = nil
                isAnalyzing = false
            }
        }

        do {
            let operation = try await MusicUnderstandingAnalyzer.makeOperation(fileURL: fileURL(for: sourceTrack))
            guard activeAnalysisID == analysisID, track?.id == sourceTrack.id else {
                await operation.cancel()
                return
            }
            activeAnalysisOperation = operation

            let result = try await operation.analyze()
            try Task.checkCancellation()
            guard activeAnalysisID == analysisID, track?.id == sourceTrack.id else { return }

            var updatedTrack = sourceTrack
            updatedTrack.analysis = result
            track = updatedTrack
            try saveTrack()
        } catch {
            guard activeAnalysisID == analysisID else { return }
            if error is CancellationError { return }
            errorMessage = error.localizedDescription
        }
    }

    func cancelAnalysis() {
        guard activeAnalysisID != nil else { return }
        let operation = activeAnalysisOperation
        activeAnalysisID = nil
        activeAnalysisOperation = nil
        isAnalyzing = false
        guard let operation else { return }
        Task { await operation.cancel() }
    }

    func removeTrack() {
        cancelAnalysis()
        player.pause()
        playbackRequested = false
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        currentTime = 0
        if let track, let audioURL = try? fileURL(for: track) {
            try? FileManager.default.removeItem(at: audioURL)
        }
        track = nil
        activeLoopID = nil
        do {
            try FileManager.default.removeItem(at: indexURL())
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSavedTrack() {
        do {
            let data = try Data(contentsOf: indexURL())
            let saved = try decoder.decode(PracticeTrack.self, from: data)
            let audioURL = try fileURL(for: saved)
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                track = saved
                errorMessage = TrackStudyError.audioFileMissing.localizedDescription
                return
            }
            track = saved
            player.replaceCurrentItem(with: AVPlayerItem(url: audioURL))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            track = nil
        } catch {
            errorMessage = "The saved track record could not be read: \(error.localizedDescription)"
        }
    }

    private func persistOrReport() {
        do { try saveTrack() }
        catch { errorMessage = error.localizedDescription }
    }

    private func wrapPlaybackLoopIfNeeded(at seconds: TimeInterval) {
        guard playbackRequested,
              !isWrappingLoop,
              let activeLoopID,
              let loop = track?.loops.first(where: { $0.id == activeLoopID }),
              seconds >= loop.endSeconds else { return }

        isWrappingLoop = true
        player.seek(
            to: CMTime(seconds: loop.startSeconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isWrappingLoop = false
                guard self.playbackRequested, self.activeLoopID == loop.id else { return }
                self.player.play()
                self.isPlaying = true
            }
        }
        currentTime = loop.startSeconds
    }

    private var activeLoop: PracticeLoop? {
        guard let activeLoopID else { return nil }
        return track?.loops.first(where: { $0.id == activeLoopID })
    }

    private var activeLoopStart: TimeInterval? {
        activeLoop?.startSeconds
    }

    private func saveTrack() throws {
        guard let track else {
            try? FileManager.default.removeItem(at: indexURL())
            return
        }
        let data = try encoder.encode(track)
        try data.write(to: indexURL(), options: .atomic)
    }

    private func baseDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("TrackStudy", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var localOnlyDirectory = directory
        try localOnlyDirectory.setResourceValues(values)
        return localOnlyDirectory
    }

    private func tracksDirectory() throws -> URL {
        let directory = try baseDirectory().appendingPathComponent("Tracks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func indexURL() throws -> URL {
        try baseDirectory().appendingPathComponent("track.json")
    }

    private func fileURL(for track: PracticeTrack) throws -> URL {
        try tracksDirectory().appendingPathComponent(track.storedFilename)
    }
}
