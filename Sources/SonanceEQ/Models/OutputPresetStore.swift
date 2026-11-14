import Foundation

struct OutputPresetStore {
    private let defaults: UserDefaults
    private static let key = "eq.outputPresets.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func preset(for uid: String) -> PresetFile? {
        presets[uid]
    }

    func set(_ preset: PresetFile?, for uid: String) throws {
        var updated = presets
        updated[uid] = preset
        defaults.set(try JSONEncoder().encode(updated), forKey: Self.key)
    }

    private var presets: [String: PresetFile] {
        guard let data = defaults.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode([String: PresetFile].self, from: data)
        else { return [:] }
        return stored
    }
}
