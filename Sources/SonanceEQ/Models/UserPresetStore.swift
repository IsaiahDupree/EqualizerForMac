import Foundation

/// A user-named EQ curve, saved locally so it survives relaunch and shows up next to the built-in
/// presets. Distinct from `PresetFile` (the portable import/export shape) — this one keeps its `id`
/// stable across a launch so the UI can select/rename/delete a specific saved preset.
struct UserPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var preampDb: Float
    var bands: [EQBand]

    init(id: UUID = UUID(), name: String, preampDb: Float, bands: [EQBand]) {
        self.id = id
        self.name = name
        self.preampDb = preampDb
        self.bands = bands
    }
}

/// Observable store for user-saved presets, persisted to `UserDefaults` — mirrors `MixerState`'s
/// pattern (injectable defaults for tests, `Codable` round-trip through a single JSON blob).
@MainActor
@Observable
final class UserPresetStore {
    private(set) var presets: [UserPreset] = []

    private let defaults: UserDefaults
    private let storeKey = "userPresets.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Save the current curve under `name`. No-ops on an empty/whitespace name or an empty band set.
    @discardableResult
    func save(name: String, preampDb: Float, bands: [EQBand]) -> UserPreset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !bands.isEmpty else { return nil }
        let preset = UserPreset(name: trimmed, preampDb: preampDb, bands: bands)
        presets.append(preset)
        persist()
        return preset
    }

    func delete(_ id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    func rename(_ id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = trimmed
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storeKey) else { return }
        presets = (try? JSONDecoder().decode([UserPreset].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: storeKey)
    }
}
