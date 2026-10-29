import Foundation
import GRDB

struct TranslationRepository {
    let db: BibleDatabase

    func all() throws -> [Translation] {
        try db.reader.read { try Translation.fetchAll($0, sql: "SELECT * FROM translations ORDER BY rowid") }
    }

    func bookNames(language: String) throws -> [BookName] {
        try db.reader.read {
            try BookName.fetchAll($0, sql: "SELECT * FROM book_names WHERE language = ? ORDER BY book", arguments: [language])
        }
    }


    /// Capítulos por libro (máximo entre todas las versiones), índice = libro-1.
    func canonicalChapterCounts() throws -> [Int] {
        try db.reader.read { d in
            var counts = [Int](repeating: 0, count: 66)
            for r in try Row.fetchAll(d, sql: "SELECT book, MAX(chapter) AS c FROM verses GROUP BY book") {
                let b: Int = r["book"]; let c: Int = r["c"]
                if (1...66).contains(b) { counts[b - 1] = c }
            }
            return counts
        }
    }

    func chapterCount(translationId: String, book: Int) throws -> Int {
        try db.reader.read {
            try Int.fetchOne($0, sql: "SELECT MAX(chapter) FROM verses WHERE translation_id = ? AND book = ?",
                             arguments: [translationId, book]) ?? 0
        }
    }
}

struct VerseRepository {
    let db: BibleDatabase

    func chapter(translationId: String, book: Int, chapter: Int) throws -> [Verse] {
        try db.reader.read {
            try Verse.fetchAll($0, sql: """
                SELECT * FROM verses WHERE translation_id = ? AND book = ? AND chapter = ? ORDER BY verse
                """, arguments: [translationId, book, chapter])
        }
    }

    func headings(translationId: String, book: Int, chapter: Int) throws -> [Heading] {
        try db.reader.read {
            try Heading.fetchAll($0, sql: """
                SELECT * FROM headings WHERE translation_id = ? AND book = ? AND chapter = ? ORDER BY rowid
                """, arguments: [translationId, book, chapter])
        }
    }

    func layout(translationId: String, book: Int, chapter: Int) throws -> [LayoutPiece] {
        try db.reader.read {
            try LayoutPiece.fetchAll($0, sql: """
                SELECT seq, kind, level, verse, text FROM layout
                WHERE translation_id = ? AND book = ? AND chapter = ? ORDER BY seq
                """, arguments: [translationId, book, chapter])
        }
    }

    func maxVerse(translationId: String, book: Int, chapter: Int) throws -> Int? {
        try db.reader.read {
            try Int.fetchOne($0, sql: "SELECT MAX(verse) FROM verses WHERE translation_id = ? AND book = ? AND chapter = ?",
                             arguments: [translationId, book, chapter])
        }
    }

    func words(translationId: String, book: Int, chapter: Int) throws -> [VerseWord] {
        try db.reader.read {
            try VerseWord.fetchAll($0, sql: """
                SELECT * FROM verse_words WHERE translation_id = ? AND book = ? AND chapter = ?
                ORDER BY verse, idx
                """, arguments: [translationId, book, chapter])
        }
    }
}

struct SearchPage {
    var hits: [SearchHit]
    var total: Int
    var perBook: [Int: Int]
}

/// Búsqueda de texto. >= 3 caracteres por término: FTS5 trigram (distingue acentos, no mayúsculas).
/// 1-2 caracteres (p. ej. 爱): LIKE sobre `verses`. Limitación conocida: "amor" no encuentra "ámor"
/// (no se pliegan acentos; ver nota en la ayuda de la búsqueda).
struct SearchRepository {
    let db: BibleDatabase

    enum Scope: Equatable { case all, ot, nt, book(Int) }

    private struct Plan {
        var terms: [String]
        var from: String
        var whereSQL: String
        var args: [DatabaseValueConvertible]
        var order: String
    }

    private func plan(_ query: String, translationId: String, scope: Scope) -> Plan? {
        let terms = SearchTerms.split(query)
        guard !terms.isEmpty else { return nil }
        var scopeSQL = ""
        var scopeArgs: [DatabaseValueConvertible] = []
        switch scope {
        case .all: break
        case .ot: scopeSQL = " AND CAST(book AS INT) <= 39"
        case .nt: scopeSQL = " AND CAST(book AS INT) >= 40"
        case .book(let b): scopeSQL = " AND CAST(book AS INT) = ?"; scopeArgs = [b]
        }
        if terms.allSatisfy({ $0.count >= 3 }) {
            let match = terms.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " OR ")
            return Plan(terms: terms, from: "verses_fts",
                        whereSQL: "verses_fts MATCH ? AND translation_id = ?" + scopeSQL,
                        args: [match, translationId] + scopeArgs,
                        order: "CAST(book AS INT), CAST(chapter AS INT), CAST(verse AS INT)")
        }
        let like = terms.map { _ in "text LIKE ? ESCAPE '\\'" }.joined(separator: " OR ")
        let pats: [DatabaseValueConvertible] = terms.map {
            "%" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_") + "%"
        }
        return Plan(terms: terms, from: "verses",
                    whereSQL: "translation_id = ? AND (\(like))" + scopeSQL,
                    args: [translationId] + pats + scopeArgs,
                    order: "book, chapter, verse")
    }

    /// "a/b" = OR.
    func search(_ query: String, translationId: String, scope: Scope = .all, limit: Int = 200) throws -> [SearchHit] {
        try page(query, translationId: translationId, scope: scope, limit: limit, withCounts: false).hits
    }

    /// Resultados (primeros `limit` en orden canónico) + recuento total y por libro.
    func page(_ query: String, translationId: String, scope: Scope = .all, limit: Int = 500,
              withCounts: Bool = true) throws -> SearchPage {
        guard let p = plan(query, translationId: translationId, scope: scope) else {
            return SearchPage(hits: [], total: 0, perBook: [:])
        }
        return try db.reader.read { d in
            let rows = try Row.fetchAll(d, sql: """
                SELECT book, chapter, verse, text FROM \(p.from) WHERE \(p.whereSQL)
                ORDER BY \(p.order) LIMIT ?
                """, arguments: StatementArguments(p.args + [limit]))
            let hits = rows.map { r -> SearchHit in
                let text: String = r["text"]
                return SearchHit(translationId: translationId, book: Self.int(r["book"]),
                                 chapter: Self.int(r["chapter"]), verse: Self.int(r["verse"]),
                                 snippet: Self.snippet(text, terms: p.terms), text: text)
            }
            var perBook: [Int: Int] = [:]
            if withCounts {
                for r in try Row.fetchAll(d, sql: """
                    SELECT book, COUNT(*) AS n FROM \(p.from) WHERE \(p.whereSQL) GROUP BY book
                    """, arguments: StatementArguments(p.args)) {
                    perBook[Self.int(r["book"])] = r["n"]
                }
            } else {
                for h in hits { perBook[h.book, default: 0] += 1 }
            }
            return SearchPage(hits: hits, total: perBook.values.reduce(0, +), perBook: perBook)
        }
    }

    private static func int(_ v: DatabaseValue) -> Int { Int.fromDatabaseValue(v) ?? Int(String.fromDatabaseValue(v) ?? "") ?? 0 }

    /// Versículo con la primera coincidencia entre «».
    static func snippet(_ text: String, terms: [String]) -> String {
        if let r = SearchHighlighter.ranges(in: text, terms: terms).first {
            var s = text
            s.replaceSubrange(r, with: "«" + text[r] + "»")
            return s
        }
        return text
    }
}

struct LexiconRepository {
    let db: BibleDatabase

    func entry(_ strong: String) throws -> LexiconEntry? {
        try db.reader.read { try LexiconEntry.fetchOne($0, sql: "SELECT * FROM lexicon WHERE id = ?", arguments: [strong]) }
    }

    /// Versículos de una traducción con ese número Strong (versículos relacionados).
    func relatedVerses(strong: String, translationId: String, limit: Int = 50) throws -> [BibleRef] {
        try db.reader.read {
            try Row.fetchAll($0, sql: """
                SELECT DISTINCT book, chapter, verse FROM verse_words
                WHERE translation_id = ? AND strong = ? ORDER BY book, chapter, verse LIMIT ?
                """, arguments: [translationId, strong, limit])
            .map { BibleRef(book: $0["book"], chapter: $0["chapter"], verseFrom: $0["verse"], verseTo: $0["verse"]) }
        }
    }

    /// Todas las apariciones (versículos distintos) de un número Strong: recuento total + primeras `limit` con su texto.
    func occurrences(strong: String, translationId: String, limit: Int = 200) throws -> (total: Int, items: [StrongOccurrence]) {
        try db.reader.read { d in
            let total = try Int.fetchOne(d, sql: """
                SELECT COUNT(*) FROM (SELECT DISTINCT book, chapter, verse FROM verse_words
                WHERE translation_id = ? AND strong = ?)
                """, arguments: [translationId, strong]) ?? 0
            let rows = try Row.fetchAll(d, sql: """
                SELECT w.book, w.chapter, w.verse, v.text FROM
                  (SELECT DISTINCT book, chapter, verse FROM verse_words WHERE translation_id = ? AND strong = ?) w
                JOIN verses v ON v.translation_id = ? AND v.book = w.book AND v.chapter = w.chapter AND v.verse = w.verse
                ORDER BY w.book, w.chapter, w.verse LIMIT ?
                """, arguments: [translationId, strong, translationId, limit])
            return (total, rows.map {
                StrongOccurrence(ref: BibleRef(book: $0["book"], chapter: $0["chapter"], verseFrom: $0["verse"], verseTo: $0["verse"]),
                                 text: $0["text"])
            })
        }
    }
}

struct CrossRefRepository {
    let db: BibleDatabase

    /// Referencias cruzadas de un versículo, de más a menos votadas.
    func refs(book: Int, chapter: Int, verse: Int) throws -> [CrossRef] {
        try db.reader.read {
            try CrossRef.fetchAll($0, sql: """
                SELECT * FROM cross_refs WHERE book = ? AND chapter = ? AND verse = ?
                ORDER BY votes DESC, to_book, to_chapter, to_verse_start
                """, arguments: [book, chapter, verse])
        }
    }

    /// Número de referencias por versículo de un capítulo (para marcar los versículos que tienen).
    func counts(book: Int, chapter: Int) throws -> [Int: Int] {
        try db.reader.read { d in
            var out: [Int: Int] = [:]
            for r in try Row.fetchAll(d, sql: """
                SELECT verse, COUNT(*) AS n FROM cross_refs WHERE book = ? AND chapter = ? GROUP BY verse
                """, arguments: [book, chapter]) {
                out[r["verse"]] = r["n"]
            }
            return out
        }
    }
}
