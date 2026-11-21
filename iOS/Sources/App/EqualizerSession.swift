import Foundation
import Observation

struct EqualizerSnapshot: Codable, Equatable {
    var settings = MobileEQSettings()
    var selectedBand = 5

    var isValid: Bool { settings.isValid && settings.bands.indices.contains(selectedBand) }
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
    let player = PreviewPlayer()
    @ObservationIgnored lazy var presets = PresetLibrary()
    private(set) var snapshot: EqualizerSnapshot
    private(set) var storageMessage: String?
    private(set) var reference: MobileEQSettings?
    private(set) var playingReference = false

    @ObservationIgnored private let store: EqualizerStore
    @ObservationIgnored private var savedSnapshot: EqualizerSnapshot
    @ObservationIgnored private var isEditing = false

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
    }

    func selectBand(_ index: Int) {
        snapshot.selectedBand = index
        if !isEditing { saveIfChanged() }
    }

    func updateEQ(_ update: (inout MobileEQSettings) -> Void) {
        update(&snapshot.settings)
        if !playingReference { player.apply(snapshot.settings) }
        if !isEditing { saveIfChanged() }
    }

    func captureReference() {
        reference = snapshot.settings
        auditionReference(false)
    }

    func auditionReference(_ enabled: Bool) {
        guard let reference else { return }
        playingReference = enabled
        player.apply(enabled ? reference : snapshot.settings)
    }

    func editingChanged(_ editing: Bool) {
        isEditing = editing
        if !editing { saveIfChanged() }
    }

    func checkpointForBackground() {
        editingChanged(false)
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
