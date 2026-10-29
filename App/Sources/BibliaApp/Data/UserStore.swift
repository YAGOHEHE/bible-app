import Foundation
import GRDB

/// ~/Library/Application Support/BibliaApp/user.sqlite (lectura/escritura, con migraciones).
final class UserStore {
    let queue: DatabaseQueue

    init(path: String) throws {
        queue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(queue)
    }

    static func defaultURL() throws -> URL {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
            .appendingPathComponent("BibliaApp", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("user.sqlite")
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE history(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  translation_id TEXT NOT NULL,
                  book INTEGER NOT NULL, chapter INTEGER NOT NULL, verse INTEGER,
                  kind TEXT NOT NULL CHECK (kind IN ('page','jump')),
                  at REAL NOT NULL);
                CREATE INDEX history_at ON history(at DESC);
                CREATE TABLE search_history(query TEXT PRIMARY KEY, at REAL NOT NULL);
                """)
        }
        return m
    }

    func addHistory(translationId: String, ref: BibleRef, kind: String, at: Date = Date()) throws {
        try queue.write {
            try $0.execute(sql: "INSERT INTO history(translation_id, book, chapter, verse, kind, at) VALUES (?,?,?,?,?,?)",
                           arguments: [translationId, ref.book, ref.chapter, ref.verseFrom, kind, at.timeIntervalSince1970])
        }
    }

    func recentHistory(limit: Int = 200) throws -> [HistoryEntry] {
        try queue.read { try HistoryEntry.fetchAll($0, sql: "SELECT * FROM history ORDER BY at DESC, id DESC LIMIT ?", arguments: [limit]) }
    }

    func clearHistory() throws { try queue.write { try $0.execute(sql: "DELETE FROM history") } }

    static let maxSearches = 50

    /// Guarda la consulta (la más reciente primero; repetida = se actualiza su fecha; máximo 50).
    func addSearch(_ q: String, at: Date = Date()) throws {
        let q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        try queue.write {
            try $0.execute(sql: "INSERT INTO search_history(query, at) VALUES (?,?) ON CONFLICT(query) DO UPDATE SET at = excluded.at",
                           arguments: [q, at.timeIntervalSince1970])
            try $0.execute(sql: """
                DELETE FROM search_history WHERE query NOT IN
                  (SELECT query FROM search_history ORDER BY at DESC, rowid DESC LIMIT ?)
                """, arguments: [Self.maxSearches])
        }
    }

    func recentSearches(limit: Int = 50) throws -> [String] {
        try queue.read { try String.fetchAll($0, sql: "SELECT query FROM search_history ORDER BY at DESC, rowid DESC LIMIT ?", arguments: [limit]) }
    }

    func clearSearches() throws { try queue.write { try $0.execute(sql: "DELETE FROM search_history") } }
}
