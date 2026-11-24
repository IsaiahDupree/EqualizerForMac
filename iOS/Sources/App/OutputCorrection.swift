import Foundation

struct PlaybackOutput: Equatable {
    let id: String
    let name: String
}

struct OutputCorrection: Codable, Equatable {
    let name: String
    let settings: MobileEQSettings
    var enabled = true

    init(preset: SavedPreset) throws {
        try self.init(name: preset.file.name, settings: MobileEQSettings(preset: preset.file))
    }

    init(preset: MobileAutoEqPreset) throws {
        try self.init(name: String(preset.displayName.prefix(100)), settings: preset.settings())
    }

    init(name: String, settings: MobileEQSettings) throws {
        self.name = try PresetLibrary.validName(name)
        self.settings = settings
        guard isValid else { throw AutoEqCatalogError.invalidPreset }
    }

    var isValid: Bool { (try? PresetLibrary.validName(name)) != nil && settings.isValid && !settings.bypassed }
}
