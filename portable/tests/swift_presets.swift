import Foundation

if CommandLine.arguments.contains("--round-trip") {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let preset = try JSONDecoder().decode(PresetFile.self, from: input)
    let encoded = try JSONEncoder().encode(preset)
    print(String(decoding: encoded, as: UTF8.self))
} else {
    let presets = Presets.all.map { PresetFile(name: $0.name, preampDb: -6, bands: $0.bands) }
    let encoded = try JSONEncoder().encode(presets)
    print(String(decoding: encoded, as: UTF8.self))
}
