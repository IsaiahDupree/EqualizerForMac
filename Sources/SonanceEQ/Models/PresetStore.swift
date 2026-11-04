import Foundation
import OSLog
import SQLite3

/// Read-only access to the bundled headphone database (AutoEq plus attributed additions).
///
/// The DB is a single SQLite file built at dev time by `Tools/build_autoeq_db.py` and shipped in the
/// app bundle. Queries are tiny (≤ a few hundred rows) and run on the main actor — instant for a UI
/// search field. The `OpaquePointer` handle is why this is `@MainActor`-isolated (it isn't Sendable).
@MainActor
final class PresetStore {
    static let shared = PresetStore()

    private var db: OpaquePointer?
    private let log = Logger(subsystem: kSubsystem, category: "PresetStore")

    /// True when the bundled DB opened successfully.
    private(set) var isAvailable = false

    private init() { open() }

    deinit {
        // sqlite3_close tolerates a nil handle.
        sqlite3_close(db)
    }

    private func open() {
        guard let url = Bundle.main.url(forResource: "autoeq", withExtension: "sqlite") else {
            log.error("autoeq.sqlite is missing from the app bundle")
            return
        }
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            isAvailable = true
            log.notice("AutoEq DB opened: \(self.totalCount, privacy: .public) presets")
        } else {
            log.error("Failed to open autoeq.sqlite: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
        }
    }

    /// Total number of presets in the DB.
    var totalCount: Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM presets", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    /// Distinct categories present, ordered by frequency (for filter chips).
    func categories() -> [String] {
        query("SELECT category FROM preset_metadata GROUP BY category ORDER BY COUNT(*) DESC", bind: [])
            .compactMap { $0 }
    }

    /// Search by model/brand (case-insensitive substring), optionally filtered to one category.
    /// Empty query returns the alphabetical head of the (filtered) library.
    func search(_ text: String, category: String? = nil, limit: Int = 200) -> [AutoEqPreset] {
        guard let db, limit > 0 else { return [] }

        var sql = """
            SELECT p.id, m.display_model, p.brand, m.category, p.source, p.preamp, p.filters,
                   m.source_url, m.data_license
            FROM presets p JOIN preset_metadata m ON p.id = m.preset_id
            """
        var clauses: [String] = []
        var binds: [String] = []

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            // Treat SQL wildcard characters literally. The secondary key handles spaces,
            // punctuation and Beats' brand aliases without inventing a model-to-curve match.
            let literal = trimmed.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let key = Self.searchKey(trimmed)
            var match = "(m.display_model LIKE ? ESCAPE '\\' COLLATE NOCASE OR p.brand LIKE ? ESCAPE '\\' COLLATE NOCASE"
            binds.append("%\(literal)%")
            binds.append("%\(literal)%")
            if !key.isEmpty {
                match += " OR m.search_key LIKE ?"
                binds.append("%\(key)%")
            }
            clauses.append(match + ")")
        }
        if let category, !category.isEmpty {
            clauses.append("m.category = ?")
            binds.append(category)
        }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY m.display_model COLLATE NOCASE, p.source COLLATE NOCASE, p.id LIMIT \(min(limit, 10_000))"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("search prepare failed: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            return []
        }
        for (i, value) in binds.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), value, -1, Self.transient)
        }

        var results: [AutoEqPreset] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(AutoEqPreset(
                id: Int(sqlite3_column_int(stmt, 0)),
                model: column(stmt, 1),
                brand: column(stmt, 2),
                category: column(stmt, 3),
                source: column(stmt, 4),
                preampDb: Float(sqlite3_column_double(stmt, 5)),
                filtersJSON: column(stmt, 6),
                sourceURL: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : URL(string: column(stmt, 7)),
                dataLicense: sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : column(stmt, 8)
            ))
        }
        return results
    }

    // MARK: - Helpers

    /// Mirrors the build-time ASCII search key. The + token matters for Studio Buds +.
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

    /// SQLITE_TRANSIENT — tells SQLite to copy bound strings (they don't outlive the call).
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func column(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }

    /// Tiny single-column string query helper (used for `categories()`).
    private func query(_ sql: String, bind: [String]) -> [String?] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        for (i, value) in bind.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), value, -1, Self.transient)
        }
        var out: [String?] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(sqlite3_column_text(stmt, 0).map { String(cString: $0) })
        }
        return out
    }
}
