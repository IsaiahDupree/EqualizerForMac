import Foundation

struct PlaybackOutput: Equatable {
    let id: String
    let name: String
}

struct PlaybackRouteFormat: Equatable {
    let sampleRateHz: Double?
    let outputChannels: Int?
    let ioBufferDurationSeconds: TimeInterval?

    init(sampleRateHz: Double, outputChannels: Int, ioBufferDurationSeconds: TimeInterval) {
        self.sampleRateHz = sampleRateHz.isFinite && sampleRateHz > 0 ? sampleRateHz : nil
        self.outputChannels = outputChannels > 0 ? outputChannels : nil
        self.ioBufferDurationSeconds = ioBufferDurationSeconds.isFinite && ioBufferDurationSeconds > 0
            ? ioBufferDurationSeconds : nil
    }

    var summary: String? {
        guard let sampleRateHz, let outputChannels, let ioBufferDurationSeconds else { return nil }
        let rate = Int(sampleRateHz.rounded())
        let bufferMilliseconds = (ioBufferDurationSeconds * 1_000).formatted(.number.precision(.fractionLength(1)))
        return "\(rate) Hz · \(outputChannels) ch · \(bufferMilliseconds) ms I/O buffer"
    }
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
