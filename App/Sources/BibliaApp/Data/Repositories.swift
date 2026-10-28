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
                SELECT * FROM headings WHERE translation_id = ? AND book = ? AND chapter = ? ORDER BY verse
                """, arguments: [translationId, book, chapter])
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

struct SearchRepository {
    let db: BibleDatabase

    enum Scope { case all, ot, nt, book(Int) }

    /// "a/b" = OR. >= 3 caracteres: FTS5 trigram (frase entre comillas). 1–2: LIKE.
    func search(_ query: String, translationId: String, scope: Scope = .all, limit: Int = 200) throws -> [SearchHit] {
        let terms = query.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        let (scopeSQL, scopeArgs): (String, [DatabaseValueConvertible]) = {
            switch scope {
            case .all: return ("", [])
            case .ot: return (" AND book <= 39", [])
            case .nt: return (" AND book >= 40", [])
            case .book(let b): return (" AND book = ?", [b])
            }
        }()
        return try db.reader.read { d in
            var hits: [SearchHit] = []
            let fts = terms.allSatisfy { $0.count >= 3 }
            let rows: [Row]
            if fts {
                let match = terms.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " OR ")
                rows = try Row.fetchAll(d, sql: """
                    SELECT book, chapter, verse, text FROM verses_fts
                    WHERE verses_fts MATCH ? AND translation_id = ?\(scopeSQL)
                    ORDER BY CAST(book AS INT), CAST(chapter AS INT), CAST(verse AS INT) LIMIT ?
                    """, arguments: StatementArguments([match, translationId] + scopeArgs + [limit]))
            } else {
                let like = terms.map { _ in "text LIKE ? ESCAPE '\\'" }.joined(separator: " OR ")
                let pats: [DatabaseValueConvertible] = terms.map {
                    "%" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
                        .replacingOccurrences(of: "_", with: "\\_") + "%"
                }
                rows = try Row.fetchAll(d, sql: """
                    SELECT book, chapter, verse, text FROM verses
                    WHERE translation_id = ? AND (\(like))\(scopeSQL)
                    ORDER BY book, chapter, verse LIMIT ?
                    """, arguments: StatementArguments([translationId] + pats + scopeArgs + [limit]))
            }
            for r in rows {
                let text: String = r["text"]
                hits.append(SearchHit(translationId: translationId, book: Self.int(r["book"]),
                                      chapter: Self.int(r["chapter"]), verse: Self.int(r["verse"]),
                                      snippet: Self.snippet(text, terms: terms)))
            }
            return hits
        }
    }

    private static func int(_ v: DatabaseValue) -> Int { Int.fromDatabaseValue(v) ?? Int(String.fromDatabaseValue(v) ?? "") ?? 0 }

    /// Fragmento con la coincidencia entre «».
    static func snippet(_ text: String, terms: [String]) -> String {
        for t in terms {
            if let r = text.range(of: t, options: [.caseInsensitive, .diacriticInsensitive]) {
                var s = text
                s.replaceSubrange(r, with: "«" + text[r] + "»")
                return s
            }
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
}
