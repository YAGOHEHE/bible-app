import Testing
import Foundation
@testable import BibliaCore

@Suite struct CrossRefTests {
    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func john316Refs() throws {
        let db = try BibleDatabase(path: try #require(BibleDatabase.bundledPath()))
        let refs = try CrossRefRepository(db: db).refs(book: 43, chapter: 3, verse: 16)
        #expect(refs.count > 10)
        // ordenadas por votos descendentes
        #expect(zip(refs, refs.dropFirst()).allSatisfy { $0.votes >= $1.votes })
        // Rom 5:8 es la más votada; 1 Jn 4:9-10 es un rango
        #expect(refs.first?.target == BibleRef(book: 45, chapter: 5, verseFrom: 8, verseTo: 8))
        let range = try #require(refs.first { $0.toBook == 62 && $0.toChapter == 4 && $0.toVerseStart == 9 })
        #expect(range.toVerseEnd == 10)
        #expect(refs.allSatisfy { $0.votes >= 0 && $0.toVerseEnd >= $0.toVerseStart })
    }

    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func countsPerVerse() throws {
        let db = try BibleDatabase(path: try #require(BibleDatabase.bundledPath()))
        let repo = CrossRefRepository(db: db)
        let counts = try repo.counts(book: 43, chapter: 3)
        let n16 = try repo.refs(book: 43, chapter: 3, verse: 16).count
        #expect((counts[16] ?? 0) == n16)
        #expect(counts.keys.allSatisfy { (1...36).contains($0) })
        let none = try repo.counts(book: 43, chapter: 999)
        #expect(none.isEmpty)
        let noRefs = try repo.refs(book: 43, chapter: 3, verse: 999)
        #expect(noRefs.isEmpty)
    }

    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func newTranslationsPresent() throws {
        let db = try BibleDatabase(path: try #require(BibleDatabase.bundledPath()))
        let ids = Set(try TranslationRepository(db: db).all().map(\.id))
        #expect(ids.isSuperset(of: ["CUV", "RV1909", "KJV", "ASV", "CUVT", "BSB", "WEB", "BLM"]))
        for t in ["CUVT", "BSB", "WEB", "BLM"] {
            let v = try VerseRepository(db: db).chapter(translationId: t, book: 43, chapter: 3).first { $0.verse == 16 }
            #expect(v != nil, "Jn 3:16 en \(t)")
        }
    }

    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func newTextsHaveTheirOwnScriptAndLanguage() throws {
        let db = try BibleDatabase(path: try #require(BibleDatabase.bundledPath()))
        let repo = VerseRepository(db: db)
        func john316(_ t: String) throws -> String { try #require(try repo.chapter(translationId: t, book: 43, chapter: 3).first { $0.verse == 16 }).text }
        let cuvt = try john316("CUVT"), cuv = try john316("CUV")
        #expect(cuvt.contains("愛") && !cuvt.contains("爱"), "CUVT debe estar en caracteres tradicionales")
        #expect(cuv.contains("爱") && !cuv.contains("愛"), "CUV debe seguir en simplificados")
        #expect(try john316("BLM").contains("amó"))
        #expect(try john316("BSB").contains("loved"))
        // Cobertura completa de cada versión nueva (66 libros)
        let n = try db.reader.read { try Int.fetchAll($0, sql: "SELECT COUNT(DISTINCT book) FROM verses WHERE translation_id IN ('CUVT','BSB','WEB','BLM') GROUP BY translation_id") }
        #expect(n.count == 4 && n.allSatisfy { $0 == 66 })
    }
}
