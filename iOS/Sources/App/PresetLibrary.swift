import Foundation
import Observation

struct SavedPreset: Codable, Identifiable {
    let id: UUID
    var file: PresetFile

    init(id: UUID = UUID(), file: PresetFile) {
        self.id = id
        self.file = file
    }
}

struct PresetCollection: Codable {
    var app = "SonanceEQ"
    var version = 1
    let presets: [PresetFile]
}

enum PresetError: LocalizedError {
    case nameRequired, nameTaken, invalidFile, tooManyFilters, outOfRange, libraryUnavailable
    case unsupportedAutoEqLine(Int)

    var errorDescription: String? {
        switch self {
        case .nameRequired: return "Enter a preset name between 1 and 100 characters."
        case .nameTaken: return "A preset with that name already exists."
        case .invalidFile: return "Choose a Sonance EQ preset, preset collection, or AutoEq ParametricEQ text file."
        case .tooManyFilters: return "Sonance EQ for iPhone supports up to \(MobileEQ.maximumBandCount) filters per preset."
        case .outOfRange: return "A filter or preamp value is outside the iPhone editor’s range."
        case .libraryUnavailable: return "Saved presets couldn’t be opened. The existing library was preserved."
        case .unsupportedAutoEqLine(let line): return "Line \(line) isn’t a supported AutoEq preamp, bell, or shelf setting."
        }
    }
}

extension MobileEQSettings {
    init(preset file: PresetFile) throws {
        self.init()
        guard file.app == "SonanceEQ", file.version == 1 else { throw PresetError.invalidFile }
        guard file.bands.count <= MobileEQ.maximumBandCount,
              (file.sideBands?.count ?? 0) <= MobileEQ.maximumBandCount else { throw PresetError.tooManyFilters }
        bands = file.eqBands()
        sideBands = file.eqSideBands() ?? Presets.flat
        preamp = file.preampDb
        midSideEnabled = file.midSideEnabled ?? false
        guard isValid else { throw PresetError.outOfRange }
    }
}

struct PresetImport {
    var files: [PresetFile] = []
    var problems: [String] = []

    static func read(_ urls: [URL]) -> PresetImport {
        var result = PresetImport()
        for url in urls {
            do {
                let files = try readFile(url)
                for file in files {
                    do {
                        _ = try MobileEQSettings(preset: file)
                        _ = try PresetLibrary.validName(file.name)
                        result.files.append(file)
                    } catch {
                        result.problems.append("\(file.name): \(error.localizedDescription)")
                    }
                }
            } catch {
                result.problems.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result
    }

    private static func readFile(_ url: URL) throws -> [PresetFile] {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let limit = 4 * 1024 * 1024
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= limit else {
            throw PresetError.invalidFile
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= limit else { throw PresetError.invalidFile }
        if url.pathExtension.lowercased() == "txt" {
            guard let text = String(data: data, encoding: .utf8) else { throw PresetError.invalidFile }
            return [try AutoEqTextPreset.read(text, name: url.deletingPathExtension().lastPathComponent)]
        }
        let decoder = JSONDecoder()
        if let collection = try? decoder.decode(PresetCollection.self, from: data),
           collection.app == "SonanceEQ", collection.version == 1, !collection.presets.isEmpty {
            return collection.presets
        }
        guard let file = try? decoder.decode(PresetFile.self, from: data) else { throw PresetError.invalidFile }
        return [file]
    }
}

@MainActor @Observable
final class PresetLibrary {
    private(set) var entries: [SavedPreset] = []
    private(set) var unavailable = false
    @ObservationIgnored private let url: URL

    init(url: URL = .applicationSupportDirectory.appending(path: "saved-presets.json")) {
        self.url = url
        do {
            let loaded = try JSONDecoder().decode([SavedPreset].self, from: Data(contentsOf: url))
            for entry in loaded {
                _ = try Self.validName(entry.file.name)
                _ = try MobileEQSettings(preset: entry.file)
            }
            entries = loaded
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            entries = []
        } catch {
            unavailable = true
        }
    }

    func save(_ settings: MobileEQSettings, name: String) throws {
        let name = try Self.validName(name)
        try ensureUnique(name, except: nil)
        let file = PresetFile(name: name, preampDb: settings.preamp, bands: settings.bands,
                              sideBands: settings.sideBands, midSideEnabled: settings.midSideEnabled)
        _ = try MobileEQSettings(preset: file)
        try commit(entries + [SavedPreset(file: file)])
    }

    func rename(_ id: UUID, to name: String) throws {
        let name = try Self.validName(name)
        try ensureUnique(name, except: id)
        try edit(id) { $0.file.name = name }
    }

    func replace(_ id: UUID, with settings: MobileEQSettings) throws {
        try edit(id) {
            $0.file = PresetFile(name: $0.file.name, preampDb: settings.preamp, bands: settings.bands,
                                 sideBands: settings.sideBands, midSideEnabled: settings.midSideEnabled)
        }
    }

    func delete(_ id: UUID) throws {
        try commit(entries.filter { $0.id != id })
    }

    func append(_ files: [PresetFile]) throws -> Int {
        var updated = entries
        let encoder = Self.encoder()
        for var file in files {
            let base = try Self.validName(file.name)
            _ = try MobileEQSettings(preset: file)
            let tuning = try encoder.encode(file.bands)
            var suffix = 2
            file.name = base
            while let existing = updated.first(where: { Self.sameName($0.file.name, file.name) }) {
                if existing.file.preampDb == file.preampDb, try encoder.encode(existing.file.bands) == tuning { break }
                let annotation = " (\(suffix))"
                file.name = String(base.prefix(100 - annotation.count)) + annotation
                suffix += 1
            }
            if !updated.contains(where: { Self.sameName($0.file.name, file.name) }) {
                updated.append(SavedPreset(file: file))
            }
        }
        let added = updated.count - entries.count
        if added > 0 { try commit(updated) }
        return added
    }

    nonisolated static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    nonisolated static func validName(_ text: String) throws -> String {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...100).contains(name.count) else { throw PresetError.nameRequired }
        return name
    }

    private func ensureUnique(_ name: String, except id: UUID?) throws {
        if entries.contains(where: { $0.id != id && Self.sameName($0.file.name, name) }) { throw PresetError.nameTaken }
    }

    private static func sameName(_ first: String, _ second: String) -> Bool {
        first.caseInsensitiveCompare(second) == .orderedSame
    }

    private func edit(_ id: UUID, update: (inout SavedPreset) -> Void) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var updated = entries
        update(&updated[index])
        _ = try MobileEQSettings(preset: updated[index].file)
        try commit(updated)
    }

    private func commit(_ updated: [SavedPreset]) throws {
        guard !unavailable else { throw PresetError.libraryUnavailable }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder().encode(updated).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        entries = updated
    }
}
