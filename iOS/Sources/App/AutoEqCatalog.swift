import Foundation
import SQLite3

/// Read-only, offline access to the attributed AutoEq and supplemental catalog.
@MainActor
final class AutoEqCatalog {
    static let shared = AutoEqCatalog(databaseURL: Bundle.main.url(forResource: "autoeq", withExtension: "sqlite"))

    private var database: OpaquePointer?
    private(set) var isAvailable = false

    var totalCount: Int {
        guard let database else { return 0 }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM presets", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    init(databaseURL: URL?) {
        guard let databaseURL else { return }
        isAvailable = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
    }

    deinit { sqlite3_close(database) }

    func categories() -> [String] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT category FROM preset_metadata GROUP BY category ORDER BY COUNT(*) DESC, category COLLATE NOCASE"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = sqlite3_column_text(statement, 0) { values.append(String(cString: value)) }
        }
        return values
    }

    func search(_ text: String, category: String? = nil, limit: Int = 100) -> [MobileAutoEqPreset] {
        guard let database, limit > 0 else { return [] }
        var clauses: [String] = []
        var bindings: [String] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let escaped = trimmed.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            var match = "(m.display_model LIKE ? ESCAPE '\\' COLLATE NOCASE OR p.brand LIKE ? ESCAPE '\\' COLLATE NOCASE"
            bindings += ["%\(escaped)%", "%\(escaped)%"]
            let key = Self.searchKey(trimmed)
            let hasLikeMetacharacter = trimmed.contains("%") || trimmed.contains("_") || trimmed.contains("\\")
            if !key.isEmpty, !hasLikeMetacharacter {
                match += " OR m.search_key LIKE ?"
                bindings.append("%\(key)%")
            }
            clauses.append(match + ")")
        }
        if let category, !category.isEmpty {
            clauses.append("m.category = ?")
            bindings.append(category)
        }

        var sql = """
            SELECT p.id, m.display_model, p.brand, m.category, p.source, p.preamp, p.filters,
                   m.source_url, m.data_license
            FROM presets p JOIN preset_metadata m ON p.id = m.preset_id
            """
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY m.display_model COLLATE NOCASE, p.source COLLATE NOCASE, p.id LIMIT \(min(limit, 500))"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        for (index, value) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, Self.transient)
        }

        var presets: [MobileAutoEqPreset] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            presets.append(MobileAutoEqPreset(
                id: Int(sqlite3_column_int(statement, 0)),
                model: Self.column(statement, 1),
                brand: Self.column(statement, 2),
                category: Self.column(statement, 3),
                source: Self.column(statement, 4),
                preampDb: Float(sqlite3_column_double(statement, 5)),
                filtersJSON: Self.column(statement, 6),
                sourceURL: sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : URL(string: Self.column(statement, 7)),
                dataLicense: sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Self.column(statement, 8)
            ))
        }
        return presets
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func column(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private static func searchKey(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().replacingOccurrences(of: "+", with: "plus")
        var key = String(folded.unicodeScalars.filter {
            (97...122).contains($0.value) || (48...57).contains($0.value)
        })
        for alias in ["beatsbydrdre", "beatsbydre"] where key.hasPrefix(alias) {
            key = "beats" + key.dropFirst(alias.count)
            break
        }
        return key
    }
}

struct MobileAutoEqPreset: Identifiable, Hashable {
    let id: Int
    let model: String
    let brand: String
    let category: String
    let source: String
    let preampDb: Float
    let filtersJSON: String
    let sourceURL: URL?
    let dataLicense: String?

    var displayName: String { "\(model) · \(source)" }

    func settings() throws -> MobileEQSettings {
        guard let data = filtersJSON.data(using: .utf8),
              let filters = try? JSONDecoder().decode([StoredFilter].self, from: data),
              !filters.isEmpty, filters.count <= MobileEQ.maximumBandCount else {
            throw AutoEqCatalogError.invalidPreset
        }
        let settings = MobileEQSettings(
            bands: filters.map { EQBand(frequency: $0.frequency, gain: $0.gain, q: $0.q, type: $0.type) },
            preamp: preampDb,
            bypassed: false
        )
        guard settings.isValid else { throw AutoEqCatalogError.invalidPreset }
        return settings
    }

    private struct StoredFilter: Decodable {
        let type: FilterType
        let frequency: Double
        let gain: Float
        let q: Double
    }
}

enum AutoEqCatalogError: LocalizedError {
    case invalidPreset

    var errorDescription: String? {
        "This headphone correction is invalid or exceeds the iPhone EQ’s supported range."
    }
}
