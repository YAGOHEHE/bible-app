import Foundation
import GRDB

/// Resaltados, notas y marcadores (por referencia, independientes de la traducción).
public final class AnnotationStore {
    private let queue: DatabaseQueue
    private let defaults: UserDefaults
    public static let lastColorKey = "ann.lastColor"

    public init(user: UserStore, defaults: UserDefaults = .standard) {
        queue = user.queue
        self.defaults = defaults
    }

    public static func now() -> Double { Date().timeIntervalSince1970 }

    public var lastUsedColor: HighlightColor {
        get { defaults.string(forKey: Self.lastColorKey).flatMap(HighlightColor.init(rawValue:)) ?? .yellow }
        set { defaults.set(newValue.rawValue, forKey: Self.lastColorKey) }
    }

    // MARK: highlights

    public func setHighlight(_ color: HighlightColor, book: Int, chapter: Int, verses: [Int], at: Double = AnnotationStore.now()) throws {
        guard !verses.isEmpty else { return }
        try queue.write { db in
            for v in Set(verses) {
                try db.execute(sql: """
                    INSERT INTO highlights(book,chapter,verse,color,updated_at) VALUES (?,?,?,?,?)
                    ON CONFLICT(book,chapter,verse) DO UPDATE SET color=excluded.color, updated_at=excluded.updated_at
                    """, arguments: [book, chapter, v, color.rawValue, at])
            }
        }
        lastUsedColor = color
    }

    public func setHighlight(_ color: HighlightColor, ref: BibleRef) throws {
        try setHighlight(color, book: ref.book, chapter: ref.chapter, verses: Self.verses(of: ref))
    }

    public func removeHighlight(book: Int, chapter: Int, verses: [Int]) throws {
        try queue.write { db in
            for v in Set(verses) {
                try db.execute(sql: "DELETE FROM highlights WHERE book=? AND chapter=? AND verse=?", arguments: [book, chapter, v])
            }
        }
    }

    public func removeHighlight(ref: BibleRef) throws { try removeHighlight(book: ref.book, chapter: ref.chapter, verses: Self.verses(of: ref)) }

    public static func verses(of ref: BibleRef) -> [Int] {
        guard let a = ref.verseFrom else { return [] }
        return Array(a...max(a, ref.verseTo ?? a))
    }

    // MARK: bookmarks

    public func isBookmarked(book: Int, chapter: Int, verse: Int) throws -> Bool {
        try queue.read { try Bool.fetchOne($0, sql: "SELECT EXISTS(SELECT 1 FROM bookmarks WHERE book=? AND chapter=? AND verse=?)",
                                           arguments: [book, chapter, verse]) ?? false }
    }

    /// Devuelve el nuevo estado (true = marcado).
    @discardableResult
    public func toggleBookmark(book: Int, chapter: Int, verse: Int) throws -> Bool {
        try queue.write { db in
            let args: StatementArguments = [book, chapter, verse]
            if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM bookmarks WHERE book=? AND chapter=? AND verse=?)", arguments: args) == true {
                try db.execute(sql: "DELETE FROM bookmarks WHERE book=? AND chapter=? AND verse=?", arguments: args)
                return false
            }
            try db.execute(sql: "INSERT INTO bookmarks(book,chapter,verse,created_at) VALUES (?,?,?,?)",
                           arguments: [book, chapter, verse, Self.now()])
            return true
        }
    }

    // MARK: notes

    /// Cuerpo vacío (solo espacios) = no se guarda y devuelve nil.
    @discardableResult
    public func addNote(book: Int, chapter: Int, verseStart: Int, verseEnd: Int? = nil, body: String, at: Double = AnnotationStore.now()) throws -> Note? {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let lo = min(verseStart, verseEnd ?? verseStart), hi = max(verseStart, verseEnd ?? verseStart)
        return try queue.write { db in
            try db.execute(sql: "INSERT INTO notes(book,chapter,verse_start,verse_end,body,created_at,updated_at) VALUES (?,?,?,?,?,?,?)",
                           arguments: [book, chapter, lo, hi, body, at, at])
            return Note(id: db.lastInsertedRowID, book: book, chapter: chapter, verseStart: lo, verseEnd: hi,
                        body: body, createdAt: at, updatedAt: at)
        }
    }

    /// Cuerpo vacío = borra la nota (devuelve nil).
    @discardableResult
    public func updateNote(id: Int64, body: String, at: Double = AnnotationStore.now()) throws -> Note? {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { try deleteNote(id: id); return nil }
        try queue.write { try $0.execute(sql: "UPDATE notes SET body=?, updated_at=? WHERE id=?", arguments: [body, at, id]) }
        return try note(id: id)
    }

    public func deleteNote(id: Int64) throws {
        try queue.write { try $0.execute(sql: "DELETE FROM notes WHERE id=?", arguments: [id]) }
    }

    public func note(id: Int64) throws -> Note? {
        try queue.read { db in try Row.fetchOne(db, sql: "SELECT * FROM notes WHERE id=?", arguments: [id]).map(Self.note) }
    }

    private static func note(_ r: Row) -> Note {
        Note(id: r["id"], book: r["book"], chapter: r["chapter"], verseStart: r["verse_start"], verseEnd: r["verse_end"],
             body: r["body"], createdAt: r["created_at"], updatedAt: r["updated_at"])
    }

    // MARK: chapter

    public func chapter(book: Int, chapter: Int) throws -> ChapterAnnotations {
        try queue.read { db in
            var out = ChapterAnnotations()
            for r in try Row.fetchAll(db, sql: "SELECT verse, color FROM highlights WHERE book=? AND chapter=?", arguments: [book, chapter]) {
                if let c = HighlightColor(rawValue: r["color"]) { out.highlights[r["verse"]] = c }
            }
            out.notes = try Row.fetchAll(db, sql: "SELECT * FROM notes WHERE book=? AND chapter=? ORDER BY verse_start, id",
                                         arguments: [book, chapter]).map(Self.note)
            out.bookmarks = Set(try Int.fetchAll(db, sql: "SELECT verse FROM bookmarks WHERE book=? AND chapter=?", arguments: [book, chapter]))
            return out
        }
    }

    // MARK: list / counts

    public func counts() throws -> AnnotationCounts {
        try queue.read { db in
            AnnotationCounts(
                notes: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes") ?? 0,
                highlights: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM highlights") ?? 0,
                bookmarks: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM bookmarks") ?? 0)
        }
    }

    public func list(_ filter: AnnotationFilter = AnnotationFilter()) throws -> [AnnotationItem] {
        let text = filter.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let kinds = filter.kinds.isEmpty ? Set(AnnotationKind.allCases) : filter.kinds
        var items: [AnnotationItem] = try queue.read { db in
            var out: [AnnotationItem] = []
            let bookSQL = filter.book == nil ? "" : " WHERE book = \(filter.book!)"
            if kinds.contains(.note) && filter.color == nil {
                for r in try Row.fetchAll(db, sql: "SELECT * FROM notes" + bookSQL) {
                    let n = Self.note(r)
                    out.append(AnnotationItem(kind: .note, book: n.book, chapter: n.chapter, verseStart: n.verseStart,
                                              verseEnd: n.verseEnd, color: nil, body: n.body, noteId: n.id, updatedAt: n.updatedAt))
                }
            }
            if kinds.contains(.highlight) && text.isEmpty {
                for r in try Row.fetchAll(db, sql: "SELECT * FROM highlights" + bookSQL) {
                    guard let c = HighlightColor(rawValue: r["color"]), filter.color == nil || filter.color == c else { continue }
                    out.append(AnnotationItem(kind: .highlight, book: r["book"], chapter: r["chapter"], verseStart: r["verse"],
                                              verseEnd: r["verse"], color: c, body: nil, noteId: nil, updatedAt: r["updated_at"]))
                }
            }
            if kinds.contains(.bookmark) && text.isEmpty && filter.color == nil {
                for r in try Row.fetchAll(db, sql: "SELECT * FROM bookmarks" + bookSQL) {
                    out.append(AnnotationItem(kind: .bookmark, book: r["book"], chapter: r["chapter"], verseStart: r["verse"],
                                              verseEnd: r["verse"], color: nil, body: nil, noteId: nil, updatedAt: r["created_at"]))
                }
            }
            return out
        }
        if !text.isEmpty {   // Unicode: sin distinguir mayúsculas ni acentos; vale para CJK.
            items = items.filter { $0.body?.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        switch filter.sort {
        case .canonical:
            items.sort { ($0.book, $0.chapter, $0.verseStart, $0.kind.rawValue) < ($1.book, $1.chapter, $1.verseStart, $1.kind.rawValue) }
        case .updated:
            items.sort { $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id < $1.id }
        }
        return items
    }
}
