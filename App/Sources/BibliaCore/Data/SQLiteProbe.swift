import Foundation
import GRDB

/// Runtime proof of which SQLite the process uses and that the features the app needs work
/// (macOS 10.13's system SQLite 3.19 has neither FTS5 trigram nor UPSERT).
public enum SQLiteProbe {
    public struct Result {
        public var version: String
        public var upsertOK: Bool
        public var trigramOK: Bool
        public var detail: String
        public var summary: String { "SQLite \(version) upsert=\(upsertOK) fts5-trigram=\(trigramOK) \(detail)" }
    }

    public static func run() -> Result {
        var r = Result(version: "?", upsertOK: false, trigramOK: false, detail: "")
        do {
            let q = try DatabaseQueue()   // in-memory
            try q.write { d in
                r.version = try String.fetchOne(d, sql: "SELECT sqlite_version()") ?? "?"
                do {
                    try d.execute(sql: "CREATE TABLE t(k TEXT PRIMARY KEY, v INTEGER)")
                    try d.execute(sql: "INSERT INTO t VALUES('a',1) ON CONFLICT(k) DO UPDATE SET v=excluded.v")
                    try d.execute(sql: "INSERT INTO t VALUES('a',2) ON CONFLICT(k) DO UPDATE SET v=excluded.v")
                    r.upsertOK = try Int.fetchOne(d, sql: "SELECT v FROM t WHERE k='a'") == 2
                } catch { r.detail += "upsert error: \(error) " }
                do {
                    try d.execute(sql: "CREATE VIRTUAL TABLE f USING fts5(text, tokenize='trigram')")
                    try d.execute(sql: "INSERT INTO f(text) VALUES ('Porque de tal manera amó Dios al mundo'), ('太初有道')")
                    let n = try Int.fetchOne(d, sql: "SELECT count(*) FROM f WHERE f MATCH '\"manera\"'") ?? 0
                    r.trigramOK = n == 1
                } catch { r.detail += "trigram error: \(error) " }
            }
        } catch { r.detail += "open error: \(error)" }
        return r
    }
}
