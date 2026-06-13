import Foundation
import OSLog
import SQLite3

/// Read-only access to the bundled AutoEq preset database (8,850 headphone corrections).
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
        query("SELECT category FROM presets GROUP BY category ORDER BY COUNT(*) DESC", bind: [])
            .compactMap { $0 }
    }

    /// Search by model/brand (case-insensitive substring), optionally filtered to one category.
    /// Empty query returns the alphabetical head of the (filtered) library.
    func search(_ text: String, category: String? = nil, limit: Int = 200) -> [AutoEqPreset] {
        guard let db else { return [] }

        var sql = "SELECT id, model, brand, category, source, preamp, filters FROM presets"
        var clauses: [String] = []
        var binds: [String] = []

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            clauses.append("(model LIKE ? COLLATE NOCASE OR brand LIKE ? COLLATE NOCASE)")
            binds.append("%\(trimmed)%")
            binds.append("%\(trimmed)%")
        }
        if let category, !category.isEmpty {
            clauses.append("category = ?")
            binds.append(category)
        }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY model COLLATE NOCASE LIMIT \(limit)"

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
                filtersJSON: column(stmt, 6)
            ))
        }
        return results
    }

    // MARK: - Helpers

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
