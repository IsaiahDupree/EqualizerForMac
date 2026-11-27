import Foundation
import Observation

struct EqualizerSnapshot: Codable, Equatable {
    var settings = MobileEQSettings()
    var selectedBand: Int? = 5
    var outputCorrections: [String: OutputCorrection]?

    var isValid: Bool {
        settings.isValid && selectedBand == settings.selection(selectedBand) &&
            (outputCorrections?.values.allSatisfy(\.isValid) ?? true)
    }
}

struct EqualizerStore {
    static let legacyKey = "sonance.eq.settings.v1"

    let file: URL
    let legacyDefaults: UserDefaults

    static var live: Self {
        Self(file: URL.applicationSupportDirectory.appending(path: "equalizer-session.json"),
             legacyDefaults: .standard)
    }

    func load() throws -> EqualizerSnapshot {
        do {
            let snapshot = try JSONDecoder().decode(EqualizerSnapshot.self, from: Data(contentsOf: file))
            guard snapshot.isValid else { throw CocoaError(.fileReadCorruptFile) }
            return snapshot
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Build 1 stored only the EQ settings, so preserve them when upgrading.
            guard let data = legacyDefaults.data(forKey: Self.legacyKey) else { return EqualizerSnapshot() }
            let settings = try JSONDecoder().decode(MobileEQSettings.self, from: data)
            guard settings.isValid else { throw CocoaError(.fileReadCorruptFile) }
            return EqualizerSnapshot(settings: settings)
        }
    }

    func save(_ snapshot: EqualizerSnapshot) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

@MainActor @Observable
final class EqualizerSession {
    static let shared = EqualizerSession()

    let player = PreviewPlayer()
    @ObservationIgnored lazy var presets = PresetLibrary()
    private(set) var snapshot: EqualizerSnapshot
    private(set) var storageMessage: String?
    private(set) var reference: MobileEQSettings?
    private(set) var playingReference = false
    private(set) var canUndo = false
    private(set) var canRedo = false

    @ObservationIgnored private let store: EqualizerStore
    @ObservationIgnored private var savedSnapshot: EqualizerSnapshot
    @ObservationIgnored private var isEditing = false
    @ObservationIgnored private var editBaseline: EqualizerSnapshot?
    @ObservationIgnored private var undoHistory: [EqualizerSnapshot] = []
    @ObservationIgnored private var redoHistory: [EqualizerSnapshot] = []
    @ObservationIgnored private var applyingHistory = false
    private static let historyLimit = 50

    init(store: EqualizerStore = .live) {
        self.store = store
        let loaded: EqualizerSnapshot
        let message: String?
        do {
            loaded = try store.load()
            message = nil
        } catch {
            loaded = EqualizerSnapshot()
            message = "Saved EQ settings couldn’t be opened."
        }
        snapshot = loaded
        savedSnapshot = loaded
        storageMessage = message
        player.apply(loaded.settings)
        player.applyOutputCorrections(loaded.outputCorrections ?? [:])
    }

    func selectBand(_ index: Int?) {
        snapshot.selectedBand = snapshot.settings.selection(index)
        if !isEditing { saveIfChanged() }
    }

    func updateEQ(_ update: (inout MobileEQSettings) -> Void) {
        var updated = snapshot.settings
        update(&updated)
        guard updated != snapshot.settings else { return }
        if isEditing && editBaseline == nil { editBaseline = snapshot }
        if !isEditing && !applyingHistory { recordUndoPoint(snapshot) }
        snapshot.settings = updated
        snapshot.selectedBand = updated.selection(snapshot.selectedBand)
        if !playingReference { player.apply(snapshot.settings) }
        if !isEditing { saveIfChanged() }
    }

    func captureReference() {
        reference = snapshot.settings
        auditionReference(false)
    }

    func applySpeechListening(_ profile: SpeechListening) {
        applyStartingSettings(profile.settings)
    }

    func applySoundStarterPreset(_ profile: SoundStarterPreset) {
        applyStartingSettings(profile.makeSettings(sampleRate: player.sampleRate))
    }

    func applyHeadphoneCorrection(_ preset: MobileAutoEqPreset) throws {
        applyStartingSettings(try preset.settings())
    }

    private func applyStartingSettings(_ settings: MobileEQSettings) {
        auditionReference(false)
        editingChanged(true)
        updateEQ { $0 = settings }
        selectBand(settings.bands.firstIndex(where: \.enabled))
        editingChanged(false)
    }

    func setEQBypass(_ bypassed: Bool) {
        auditionReference(false)
        editingChanged(true)
        updateEQ { $0.bypassed = bypassed }
        editingChanged(false)
    }

    func correction(for output: PlaybackOutput) -> OutputCorrection? {
        snapshot.outputCorrections?[output.id]
    }

    @discardableResult
    func setCorrection(_ correction: OutputCorrection?, for output: PlaybackOutput) -> Bool {
        // The assignment belongs to the captured output identity. A route can
        // change while the correction sheet is open; preserve the user's edit
        // for that output, while PreviewPlayer applies it only when that exact
        // identity is active again.
        guard !output.id.isEmpty, correction?.isValid != false else { return false }
        var assignments = snapshot.outputCorrections ?? [:]
        if let correction {
            assignments[output.id] = correction
        } else {
            assignments.removeValue(forKey: output.id)
        }
        var updated = snapshot
        updated.outputCorrections = assignments.isEmpty ? nil : assignments
        guard updated != snapshot else { return true }
        recordUndoPoint(snapshot)
        snapshot = updated
        player.applyOutputCorrections(assignments)
        saveIfChanged()
        return true
    }

    func auditionReference(_ enabled: Bool) {
        guard let reference else { return }
        playingReference = enabled
        player.apply(enabled ? reference : snapshot.settings)
    }

    func editingChanged(_ editing: Bool) {
        if editing && !isEditing {
            editBaseline = snapshot
        } else if !editing && isEditing, let baseline = editBaseline, baseline != snapshot,
                  !applyingHistory {
            recordUndoPoint(baseline)
        }
        isEditing = editing
        if !editing {
            editBaseline = nil
            saveIfChanged()
        }
    }

    func undo() {
        finishEditingForHistory()
        guard let previous = undoHistory.popLast() else { return }
        auditionReference(false)
        redoHistory.append(snapshot)
        restoreFromHistory(previous)
        updateHistoryAvailability()
    }

    func redo() {
        finishEditingForHistory()
        guard let next = redoHistory.popLast() else { return }
        auditionReference(false)
        undoHistory.append(snapshot)
        restoreFromHistory(next)
        updateHistoryAvailability()
    }

    func checkpointForBackground() {
        editingChanged(false)
    }

    private func finishEditingForHistory() {
        if isEditing { editingChanged(false) }
    }

    private func recordUndoPoint(_ point: EqualizerSnapshot) {
        guard !applyingHistory else { return }
        undoHistory.append(point)
        if undoHistory.count > Self.historyLimit { undoHistory.removeFirst(undoHistory.count - Self.historyLimit) }
        redoHistory.removeAll(keepingCapacity: true)
        updateHistoryAvailability()
    }

    private func restoreFromHistory(_ restored: EqualizerSnapshot) {
        applyingHistory = true
        snapshot = restored
        player.apply(snapshot.settings)
        player.applyOutputCorrections(snapshot.outputCorrections ?? [:])
        saveIfChanged()
        applyingHistory = false
    }

    private func updateHistoryAvailability() {
        canUndo = !undoHistory.isEmpty
        canRedo = !redoHistory.isEmpty
    }

    private func saveIfChanged() {
        guard snapshot != savedSnapshot else { return }
        do {
            try store.save(snapshot)
            savedSnapshot = snapshot
            storageMessage = nil
        } catch {
            storageMessage = "Your latest EQ settings couldn’t be saved."
        }
    }
}
