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
        name = try PresetLibrary.validName(preset.file.name)
        settings = try MobileEQSettings(preset: preset.file)
    }

    var isValid: Bool { (try? PresetLibrary.validName(name)) != nil && settings.isValid && !settings.bypassed }
}
